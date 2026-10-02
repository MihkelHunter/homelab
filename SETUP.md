# Pisiketeenus Homelab — Setup Guide

Hosts two family apps behind a single shared login on a cheap Hetzner Cloud VPS:

- **gochecklist** -> `https://checklist.pisiketeenus.eu`
- **goweather** -> `https://weather.pisiketeenus.eu`
- gocalories -> `https://calories.pisiketeenus.eu`
Stack: Hetzner Cloud CX22
· Docker Compose
· Caddy (reverse proxy + Let's Encrypt HTTPS + basicauth).

```
Internet → Caddy (80/443 only)
                 ├── gochecklist (:8081)
                 └── goweather   (:7001)
```

## Local testing (run on your machine)

You can run the whole stack locally before (or instead of) deploying to a VPS.
The two apps build from the `gochecklist/` and `goweather/` directories in this
repo; only the Caddy config changes for local use.

### Files

| Path | Purpose |
| ------ | --------- |
| `caddy/Caddyfile.local` | Local reverse proxy: `*.localhost` sites + port-only sites for Tailscale |
| `docker-compose.local.yml` | Compose overlay: mounts `Caddyfile.local`, injects `.env` into Caddy, remaps ports |
| `run-local.sh` / `run-local.ps1` | Start the local stack (no Tailscale) |
| `docker-compose.tailscale.yml` | Optional overlay (profile `tailscale`): Tailscale sidecar on your tailnet |
| `run-tailscale.sh` / `run-tailscale.ps1` | Start the local stack with Tailscale enabled |
| `tailscale/ts-serve.json` | `tailscale serve` config: 4 tailnet ports → 4 Caddy ports |
| `.env` (gitignored) | Same shape as `.env.example`; see below |

### Steps

1. Copy `.env.example` to `.env`:

   ```bash
   cp .env.example .env
   ```

2. Edit `.env`:

   ```bash
   AUTH_USER=family                          # shared login username
   AUTH_PASSWORD_HASH=$2a$14$...             # hash for your local password
   ACME_EMAIL=you@example.com                # unused locally (internal TLS)
   ```

   Generate the hash with:

   ```bash
   docker run --rm caddy:2.9-alpine caddy hash-password
   ```

   > Docker Compose interpolates `$` in `.env`, so if the hash contains `$`
   > (it always does, e.g. `$2a$14$EXP...`), write it as `$$2a$$14$$EXP...`
   > and Compose will convert it back to a single `$` in the container.

3. Start the stack:

   ```bash
   ./run-local.sh              # or: .\run-local.ps1
   ```

   That is just a wrapper for:

   ```bash
   docker compose -f docker-compose.yml -f docker-compose.local.yml up --build --remove-orphans
   ```

4. Open the apps (login with `AUTH_USER` / your password):

   - `https://checklist.localhost:8443`
   - `https://weather.localhost:8443`

### Notes

- Ports bound: HTTP on **80/8080**, HTTPS on **443/8443** (both sets work;
  edit `ports` in `docker-compose.local.yml` if 80/443 are taken).
- Local Caddy uses its **internal CA** (`tls internal`), so no Let's Encrypt or
  ACME email is needed; `auto_https disable_redirects` turns off the
  HTTP→HTTPS redirect so the non-standard ports work.
- Browsers will warn about the self-signed internal cert on first visit —
  accept it once, or trust Caddy's local CA stored in the `caddy_data` volume.
- `*.localhost` resolves to `127.0.0.1` in modern browsers, so no `/etc/hosts`
  edits are needed.
- App data persists in the same named volumes (`gochecklist_data`,
  `goweather_data`) as on the server.
- Stop with `docker compose -f docker-compose.yml -f docker-compose.local.yml down`.
- The `Caddyfile.local` / overlay never touch the production `Caddyfile`, so
  deploy-to-server flow below is unaffected.

---

## Tailscale (local hosting only)

Optionally publish the local stack on your **tailnet** instead of on the public
internet — useful for testing from your phone, or for a family VPS-less setup.
Nothing is exposed outside the tailnet and no ports change on your machine.

**The feature flag is the Compose profile `tailscale`** (not an env var, not a
file rename), so switching it off restores the previous state exactly:

```bash
# ON  — or just: ./run-tailscale.sh   (or: .\run-tailscale.ps1)
docker compose -f docker-compose.yml -f docker-compose.local.yml \
  -f docker-compose.tailscale.yml --profile tailscale up --build

# OFF — or just: ./run-local.sh       (or: .\run-local.ps1)
docker compose -f docker-compose.yml -f docker-compose.local.yml up --build

# OFF + drop the tailnet node from your account entirely
docker compose -f docker-compose.yml -f docker-compose.local.yml \
  -f docker-compose.tailscale.yml --profile tailscale \
  down --volumes --remove-orphans
```

The `:908x` sites at the bottom of `caddy/Caddyfile.local` are the only
permanent change and they are inert while the profile is off: the ports are not
published on the host, so nothing outside the compose network can reach them.

### Files

| Path | Purpose |
| ------ | --------- |
| `docker-compose.tailscale.yml` | Adds the `tailscale` service (profile `tailscale`) sharing Caddy's netns |
| `run-tailscale.sh` / `run-tailscale.ps1` | Starts the stack with the profile on; checks `TAILSCALE_AUTHKEY` first |
| `tailscale/ts-serve.json` | Serve config: tailnet HTTPS ports → Caddy ports |
| `caddy/Caddyfile.local` | Last 4 blocks: port-only sites on 9080-9083 for Tailscale Serve |

### Setup

1. Create a Tailscale auth key at
   <https://login.tailscale.com/admin/settings/keys> and add it to `.env`:

   ```bash
   TAILSCALE_AUTHKEY=tskey-auth-xxxxxxxxxxxxxxxx?ephemeral=true
   TS_HOSTNAME=homelab            # -> https://homelab.<tailnet>.ts.net
   ```

   `?ephemeral=true` makes the node drop out of your other devices' lists when
   the stack is down. HTTPS must be enabled for the tailnet so Serve can issue
   the certificate.

2. Start with `./run-tailscale.sh` (or `.\run-tailscale.ps1`), then confirm:

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml \
  -f docker-compose.tailscale.yml --profile tailscale \
  exec tailscale tailscale serve status
```

### URLs

`tailscale serve` terminates TLS with a real, publicly-trusted certificate for
the node's `ts.net` name, then proxies plain HTTP to Caddy on loopback. Tailscale
only issues certs for `<node>.<tailnet>.ts.net` — never for subdomains of it — so
each app gets its own port instead of its own hostname:

| App | URL |
| --- | --- |
| gochecklist | `https://homelab.<tailnet>.ts.net/` |
| goweather | `https://homelab.<tailnet>.ts.net:8443` |
| gocalories | `https://homelab.<tailnet>.ts.net:9443` |
| messaging (WhatsApp) | `https://homelab.<tailnet>.ts.net:10443` |

Basicauth still applies, so keep using `AUTH_USER` + your password. The
`*.localhost:8443` URLs keep working at the same time — the two share Caddy.

### Can you run `tailscale serve` from inside the container?

Yes, the CLI is in the image. `serve` can only proxy to `http://127.0.0.1`, which
is why the sidecar uses `network_mode: service:caddy` — it lives in Caddy's
network namespace, so `127.0.0.1:9080` is Caddy's loopback listener:

```bash
TS="docker compose -f docker-compose.yml -f docker-compose.local.yml \
  -f docker-compose.tailscale.yml --profile tailscale"

# inspect what is served
$TS exec tailscale tailscale serve status

# add an endpoint at runtime (not persisted — see below)
$TS exec tailscale tailscale serve --https=11443 http://127.0.0.1:9082

# tear down all serve config (leaves the node on your tailnet)
$TS exec tailscale tailscale serve reset
```

Runtime changes are lost on container restart, because `TS_SERVE_CONFIG` points
at `tailscale/ts-serve.json`. To make an endpoint stick, run the same command
with `serve set-config` or just edit that file — the `${TS_CERT_DOMAIN}`
placeholder is substituted by `tailscaled` at load time, so you never hardcode
the tailnet name.

### Notes

- `TS_EXTRA_ARGS=--accept-dns=false` is required: the sidecar shares Caddy's
  network namespace, and letting `tailscaled` manage DNS there would break
  Caddy's resolution of the `gochecklist` / `goweather` service names.
- `cap_add: net_admin` + `/dev/net/tun` are for the kernel WireGuard engine. If
  your Docker host cannot provide `/dev/net/tun`, set `TS_USERSPACE=true` in the
  sidecar's environment (Serve still works in userspace mode).
- Node state lives in the `tailscale_state` volume, so restarts don't re-auth.
- The sidecar has no `networks:` key of its own — it is reachable only through
  Caddy's namespace, never from the `edge` network.
- **After `docker compose restart caddy`, restart the sidecar too.** It shares
  Caddy's network namespace, so it can come back up with a namespace that has no
  working interface (`magicsock: network down`, all URLs time out). Or just run
  `docker compose ... up -d`, which recreates both in the right order.

---

## Server deployment (Hetzner VPS)

### Prerequisites

- A **Hetzner Cloud account** at console.hetzner.com
- The domain **pisiketeenus.eu** (DNS can be managed in Hetzner's console)
- You have already scaffolded the files in this repo
(docker-compose.yml, caddy/, deploy.sh, setup.sh, .env.example)

## 1. Create the VPS

1. Sign in at **console.hetzner.com** → Projects → New Project.
2. **Add Server**:
   - Location: closest to your users (EU: Nuremberg/Falkenstein/Helsinki, US: Ashburn/Hillsboro)
   - Image: **Ubuntu 24.04**
   (or the one-click **Docker CE** app if you prefer Docker preinstalled)
   - Type: **CX22** (2 vCPU, 4 GB RAM, 40 GB NVMe) — ~€4.50/month
   - Add an **SSH key** (or use the emailed root password)
   - Backup: optional (snapshots are handy before big changes)
3. Note the server's **public IPv4 address**.

## 2. DNS

In Hetzner Console → your **domain zone** (`pisiketeenus.eu`),
add these records pointing at the server IP:

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

> If you add `env_file: [.env]` to the caddy service (see Troubleshooting),
> escape `$` as `$$` in this file the same way as in the local setup above.

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

## Deploy Files

| Path | Purpose |
| ------ | --------- |
| `docker-compose.yml` | Caddy + both apps; only Caddy exposes ports |
| `caddy/Caddyfile` | Reverse proxy, basicauth, auto-HTTPS |
| `.env` / `.env.example` | Secrets & ACME email (**never commit `.env`**) |
| `deploy.sh` | Pull → build → restart |
| `setup.sh` | One-time bootstrap (Docker, clone, .env, hash) |
| `gochecklist/Dockerfile` + `entrypoint.sh` | App image (CGO build, templates on volume) |
| `goweather/Dockerfile` + `entrypoint.sh` | App image (static build, WhatsApp session on volume) |

## Cost

| Item | ~Monthly |
| ------ | ---------- |
| Hetzner CX22 | €4.50 |
| Domain (annual) | ~€1 |
| TLS certs (Let's Encrypt) | €0 |
| **Total** | **~€5–6** |

## Troubleshooting

- **Certificate not issued / redirect loop** → DNS not propagated or port 80 blocked.
Verify `dig checklist.pisiketeenus.eu`, and that 80 is open.
- **401 after login** → wrong `AUTH_PASSWORD_HASH`; regenerate and redeploy.
- **Always 401 (even with wrong password attempt) / no ACME email** → Caddy can't
  read `.env`. The `caddy` service in `docker-compose.yml` must receive the vars
  from `.env` (add `env_file: [.env]` to the caddy service) — otherwise
  `{$AUTH_USER}`, `{$AUTH_PASSWORD_HASH}` and `{$ACME_EMAIL}` are empty. Verify
  with `docker compose exec caddy env`.
- **Changes not showing** → run `./deploy.sh` (rebuilds the images from latest git).
