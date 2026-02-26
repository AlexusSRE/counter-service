#!/usr/bin/env bash
# Stop the Vintage Story server (run from repo root or vintagestory-server/)

set -e
cd "$(dirname "$0")/.."
docker compose down
echo "Server stopped. Data is in ./data"
