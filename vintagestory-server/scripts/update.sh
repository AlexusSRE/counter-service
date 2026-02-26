#!/usr/bin/env bash
# Rebuild image (with current VS_VERSION from .env) and restart the server.
# Run from repo root or vintagestory-server/

set -e
cd "$(dirname "$0")/.."
echo "Stopping server..."
docker compose down
echo "Rebuilding image (VS_VERSION from .env)..."
docker compose build --no-cache
echo "Starting server..."
docker compose up -d
echo "Update done. Check logs: docker compose logs -f"
