#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "==> Pulling latest code..."
git pull

echo "==> Building images..."
docker compose build

echo "==> Restarting stack..."
docker compose up -d

echo "==> Pruning dangling images..."
docker image prune -f

echo "==> Status:"
docker compose ps
