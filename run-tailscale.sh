#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if ! grep -qE '^TAILSCALE_AUTHKEY=..+' .env 2>/dev/null; then
	echo "TAILSCALE_AUTHKEY is missing from .env - see .env.example" >&2
	exit 1
fi

# The `tailscale` profile is the feature flag for the tailnet-only sidecar.
docker compose \
	-f docker-compose.yml \
	-f docker-compose.local.yml \
	-f docker-compose.tailscale.yml \
	--profile tailscale \
	up --build