#!/bin/bash
# Bootstrap script for the Pisiketeenus homelab on a fresh Hetzner Cloud server.
# Installs Docker, clones the repos, and starts the stack.
#
# Usage:  sudo bash setup.sh   (run as root or with sudo on the VPS)
set -euo pipefail

# ---------------------------------------------------------------------------
# Config - edit these before running on the server.
# ---------------------------------------------------------------------------
# HTTPS/ACME cert registration + expiry notice email
ACME_EMAIL="${ACME_EMAIL:-}"
# Shared family login used by Caddy basicauth on both apps
AUTH_USER="${AUTH_USER:-family}"
# Git repo URLs (must be public or reachable without credentials)
COMPOSE_REPO="${COMPOSE_REPO:-}"            # repo holding docker-compose.yml, caddy/, deploy.sh
GOCHECKLIST_REPO="${GOCHECKLIST_REPO:-https://github.com/MihkelHunter/gochecklist.git}"
GOWEATHER_REPO="${GOWEATHER_REPO:-https://github.com/MihkelHunter/goweather.git}"
# Where the stack lives on the server
DEPLOY_DIR="${DEPLOY_DIR:-/opt/homelab}"
# User that will own the folder and run docker (defaults to the sudo caller)
APP_USER="${SUDO_USER:-root}"

log()  { echo -e "\033[1;32m==>\033[0m $*"; }
warn() { echo -e "\033[1;33m==>\033[0m $*"; }
fail() { echo -e "\033[1;31m==>\033[0m $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Run as root:  sudo bash setup.sh"
[ -n "$ACME_EMAIL" ] || warn "ACME_EMAIL is empty - HTTPS cert issuance will fail. Edit the top of setup.sh first."
[ -n "$COMPOSE_REPO" ] || warn "COMPOSE_REPO is empty - the composition files must be copied/placed manually into $DEPLOY_DIR."

# ---------------------------------------------------------------------------
# 1. Install Docker Engine + compose plugin + git (Ubuntu 24.04)
# ---------------------------------------------------------------------------
log "Installing Docker Engine, compose plugin, and git..."
if ! command -v docker >/dev/null 2>&1; then
  apt-get update
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin git
else
  log "Docker already installed; installing git if missing..."
  command -v git >/dev/null 2>&1 || apt-get install -y git
fi

# Allow APP_USER to run docker without sudo
if [ "$APP_USER" != "root" ]; then
  usermod -aG docker "$APP_USER" || true
  log "Added $APP_USER to the docker group (log out/in required for non-sudo docker)."
fi
systemctl enable --now docker

# ---------------------------------------------------------------------------
# 2. Create the deploy directory and fetch the code
# ---------------------------------------------------------------------------
mkdir -p "$DEPLOY_DIR"
cd "$DEPLOY_DIR"

log "Cloning app repos into $DEPLOY_DIR..."
[ -d gochecklist/.git ] || git clone "$GOCHECKLIST_REPO" gochecklist
[ -d goweather/.git ]   || git clone "$GOWEATHER_REPO"   goweather

if [ -n "$COMPOSE_REPO" ] && [ ! -f docker-compose.yml ]; then
  log "Cloning composition repo into $DEPLOY_DIR..."
  tmp="$(mktemp -d)"
  git clone "$COMPOSE_REPO" "$tmp/compose"
  # Bring the composition files up into DEPLOY_DIR without clobbering app repos.
  cp "$tmp/compose"/docker-compose.yml "$tmp/compose"/deploy.sh "$tmp/compose"/SETUP.md \
     "$tmp/compose"/.env.example "$tmp/compose"/.gitignore "$DEPLOY_DIR/" 2>/dev/null || true
  mkdir -p "$DEPLOY_DIR/caddy"
  cp -rf "$tmp/compose/caddy/." "$DEPLOY_DIR/caddy/" 2>/dev/null || true
  rm -rf "$tmp"
fi

[ -f docker-compose.yml ] || fail "No docker-compose.yml found in $DEPLOY_DIR. Provide COMPOSE_REPO or copy the files."

chown -R "$APP_USER":"$APP_USER" "$DEPLOY_DIR" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 3. Configure .env (never commit this file)
# ---------------------------------------------------------------------------
if [ ! -f .env ]; then
  cp .env.example .env
  log "Created .env from .env.example - edit it and continue."
else
  log ".env already exists."
fi

log "Generating a basicauth password hash for '$AUTH_USER'..."
HASH="$(docker run --rm caddy:2.9-alpine caddy hash-password 2>/dev/null || true)"
if [ -n "$HASH" ]; then
  warn "Run this to insert it into .env (paste the \$2a\$... value):"
  echo "      sed -i 's|^AUTH_PASSWORD_HASH=.*|AUTH_PASSWORD_HASH=\"$HASH\"|' $DEPLOY_DIR/.env"
fi

# ---------------------------------------------------------------------------
# 4. Final steps
# ---------------------------------------------------------------------------
cat <<EOF

============================================================
  Setup is staged. To finish:
   1) Fill in $DEPLOY_DIR/.env  (ACME_EMAIL, AUTH_USER, AUTH_PASSWORD_HASH)
   2) Point DNS at this server's public IP:
          pisiketeenus.eu             -> <server-ip>
          checklist.pisiketeenus.eu   -> <server-ip>
          weather.pisiketeenus.eu     -> <server-ip>
   3) Open ports in the Hetzner firewall:  80/tcp  443/tcp  443/udp
   4) Run:   cd $DEPLOY_DIR && sudo ./deploy.sh
============================================================
EOF
