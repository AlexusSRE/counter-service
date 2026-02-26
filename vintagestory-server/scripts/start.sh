#!/usr/bin/env bash
# Start the Vintage Story server (run from repo root or vintagestory-server/)

set -e
cd "$(dirname "$0")/.."
mkdir -p data
docker compose up -d
echo "Server starting. Game port: 42420 (tcp/udp). Logs: docker compose logs -f"
