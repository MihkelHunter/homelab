#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# --remove-orphans drops the tailscale sidecar when the tailnet variant ran before.
docker compose \
	-f docker-compose.yml \
	-f docker-compose.local.yml \
	up --build --remove-orphans