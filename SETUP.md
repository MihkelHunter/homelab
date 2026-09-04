# Pisiketeenus Homelab — Setup Guide

Hosts two family apps behind a single shared login on a cheap Hetzner Cloud VPS:

- **gochecklist** → `https://checklist.pisiketeenus.eu`
- **goweather** → `https://weather.pisiketeenus.eu`

Stack: Hetzner Cloud CX22 · Docker Compose · Caddy (reverse proxy + Let's Encrypt HTTPS + basicauth).

```
Internet → Caddy (80/443 only)
                 ├── gochecklist (:8081)
                 └── goweather   (:7001)
```

## Prerequisites

- A **Hetzner Cloud account** at console.hetzner.com
- The domain **pisiketeenus.eu** (DNS can be managed in Hetzner's console)
- You have already scaffolded the files in this repo (docker-compose.yml, caddy/, deploy.sh, setup.sh, .env.example)

## 1. Create the VPS

1. Sign in at **console.hetzner.com** → Projects → New Project.
2. **Add Server**:
   - Location: closest to your users (EU: Nuremberg/Falkenstein/Helsinki, US: Ashburn/Hillsboro)
   - Image: **Ubuntu 24.04** (or the one-click **Docker CE** app if you prefer Docker preinstalled)
   - Type: **CX22** (2 vCPU, 4 GB RAM, 40 GB NVMe) — ~€4.50/month
   - Add an **SSH key** (or use the emailed root password)
   - Backup: optional (snapshots are handy before big changes)
3. Note the server's **public IPv4 address**.

## 2. DNS

In Hetzner Console → your **domain zone** (`pisiketeenus.eu`), add these records pointing at the server IP:

| Type | Name | Value |
|------|------|-------|
| A    | `@`        | `<server-ip>` |
| A    | `checklist`| `<server-ip>` |
| A    | `weather`  | `<server-ip>` |

## 3. Firewall

Open only the ports the proxy needs (Hetzner > your server > Firewall):

- `22/tcp` — SSH (restrict to your IP if you like)
- `80/tcp`  — HTTP (Let's Encrypt ACME challenge)
- `443/tcp` — HTTPS
- `443/udp` — HTTP/3 (optional)

## 4. Bootstrap the stack

SSH in and run the bootstrap script:

```bash
ssh root@<server-ip>
sudo bash -c '
  apt-get update && apt-get install -y git
  git clone <your-compose-repo-url> /opt/homelab
  cd /opt/homelab
  ./setup.sh
'
```

> If you don't have the compose files in a repo yet, just copy this whole `homelab/`
> folder up to `/opt/homelab` instead of the `git clone` above.

`setup.sh` will:
- Install Docker Engine + Compose plugin + git
- Clone the two app repos (`gochecklist`, `goweather`) into `/opt/homelab/`
- Create `.env` from `.env.example`
- Generate a **basicauth password hash** for the shared family login

## 5. Configure `.env`

Edit `/opt/homelab/.env` and set:

```bash
ACME_EMAIL=you@example.com              # Let's Encrypt notice email (required for HTTPS)
AUTH_USER=family                        # shared login username
AUTH_PASSWORD_HASH=$2a$14$...           # paste the hash from setup.sh, or generate one:
#   docker run --rm caddy:2.9-alpine caddy hash-password
```

## 6. Deploy

```bash
cd /opt/homelab
sudo ./deploy.sh
```

`deploy.sh` pulls latest code, rebuilds, restarts the stack, and shows container status.
On first boot Caddy talks to Let's Encrypt and provisions certs for both subdomains.

Check it works:

```bash
docker compose ps
docker compose logs -f caddy        # watch for certificate issuance
```

Then open the two URLs — you'll be asked for the shared `AUTH_USER` / password.

## Updating later

```bash
cd /opt/homelab && sudo ./deploy.sh
```

## Files

| Path | Purpose |
|------|---------|
| `docker-compose.yml` | Caddy + both apps; only Caddy exposes ports |
| `caddy/Caddyfile` | Reverse proxy, basicauth, auto-HTTPS |
| `.env` / `.env.example` | Secrets & ACME email (**never commit `.env`**) |
| `deploy.sh` | Pull → build → restart |
| `setup.sh` | One-time bootstrap (Docker, clone, .env, hash) |
| `gochecklist/Dockerfile` + `entrypoint.sh` | App image (CGO build, templates on volume) |
| `goweather/Dockerfile` + `entrypoint.sh` | App image (static build, WhatsApp session on volume) |

## Cost

| Item | ~Monthly |
|------|----------|
| Hetzner CX22 | €4.50 |
| Domain (annual) | ~€1 |
| TLS certs (Let's Encrypt) | €0 |
| **Total** | **~€5–6** |

## Troubleshooting

- **Certificate not issued / redirect loop** → DNS not propagated or port 80 blocked. Verify `dig checklist.pisiketeenus.eu`, and that 80 is open.
- **401 after login** → wrong `AUTH_PASSWORD_HASH`; regenerate and redeploy.
- **Changes not showing** → run `./deploy.sh` (rebuilds the images from latest git).
