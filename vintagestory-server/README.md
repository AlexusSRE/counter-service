# Vintage Story dedicated server (Docker)

A minimal Docker setup for running a **Vintage Story** dedicated server at home, with persistent data, a 1.4 GB memory cap, optional SSH, and simple scripts.

## What’s included

- **Custom image**: Debian-based image that downloads the official Vintage Story server from the CDN (version set via `VS_VERSION`).
- **Persistent storage**: All server data (saves, config, logs, mods) lives under `./data` on the host (bind mount) and survives restarts and container recreates.
- **Memory limit**: Container is limited to **1.4 GB** using `mem_limit` (see [Memory limit](#memory-limit) below).
- **Ports**: Game on **42420** (TCP and UDP). Optional SSH on host **42421** → container 22.
- **Restart policy**: `unless-stopped`.
- **Healthcheck**: TCP check on port 42420 every 30s.

---

## Quick start

1. **Create the data directory** (required before first run):

   ```bash
   mkdir -p data
   ```

2. **Copy and edit environment** (optional):

   ```bash
   cp .env .env.local
   # Edit .env.local: server name, password, admin user, timezone, etc.
   ```

3. **Start the server**:

   ```bash
   docker compose --env-file .env.local up -d
   ```
   Or use the default `.env`:
   ```bash
   docker compose up -d
   ```

4. **Connect** from Vintage Story: multiplayer → add server → `YOUR_IP:42420`.

---

## Commands

Run these from the `vintagestory-server/` directory (where `docker-compose.yml` lives).

| Action | Command |
|--------|--------|
| **Start** | `docker compose up -d` |
| **Stop** | `docker compose down` |
| **View logs** | `docker compose logs -f` |
| **Restart** | `docker compose restart` |
| **Rebuild image (e.g. after changing Dockerfile)** | `docker compose build --no-cache && docker compose up -d` |

Optional helper scripts (run from `vintagestory-server/`):

```bash
# On Linux, make scripts executable once (and fix line endings if you see "command not found"):
chmod +x scripts/*.sh
# If scripts were edited on Windows, strip CRLF:  sed -i 's/\r$//' scripts/*.sh

./scripts/start.sh    # start
./scripts/stop.sh     # stop
./scripts/update.sh   # rebuild and restart
```

---

## Troubleshooting (Linux / Raspberry Pi)

- **Permission denied** when running `./start.sh`: make the scripts executable:
  ```bash
  chmod +x scripts/*.sh
  ```
- **`sudo: ./start.sh: command not found`** (or similar): the script likely has Windows line endings (CRLF). Strip them:
  ```bash
  sed -i 's/\r$//' scripts/*.sh
  ```
  Then run `./scripts/start.sh` again (no need for `sudo` to run the script; use `sudo` only for Docker if your user isn’t in the `docker` group).
- **"default group code suplayer but no such group exists"**: the generated `serverconfig.json` was missing the `Roles` array and `DefaultRoleCode`. Either remove `./data/serverconfig.json` and restart (the entrypoint will create a valid one), or add a `"DefaultRoleCode": "suplayer"` and a `Roles` array that includes a role with `"Code": "suplayer"` (see the [Server Config](https://wiki.vintagestory.at/Server_Config) wiki).

---

## Running on ARM (Raspberry Pi, etc.)

The **official** Vintage Story server is **x64-only**. You have two options on ARM:

### Option A: x64 emulation (default, works out of the box)

The compose file sets **`platform: linux/amd64`**, so Docker runs the x64 server under **QEMU emulation** on your Pi. No extra config.

- **Requires:** QEMU user emulation (often already set up with Docker on Raspberry Pi OS; if not, install `qemu-user-static` and register binfmt).
- **Trade-off:** Some CPU overhead; usually fine for a few players.

Just run as usual:

```bash
docker compose up -d
```

### Option B: Native ARM64 (follows [anegostudios/VintagestoryServerArm64](https://github.com/anegostudios/VintagestoryServerArm64))

We follow the **official experimental repo**: build stage gets the official server tarball, removes x64 binaries and `Lib`, then **clones their repo and copies the `server/` folder** (ARM64 binaries). Runtime uses the **official Microsoft .NET 8 image** (`mcr.microsoft.com/dotnet/runtime:8.0`). Data path is their default: `/home/vintagestory/.config/VintagestoryData` (no custom entrypoint; server creates config on first run).

In `.env` set:

- `VS_DOCKERFILE=Dockerfile.arm64`
- `VS_PLATFORM=linux/arm64`
- `VS_DATA_MOUNT=/home/vintagestory/.config/VintagestoryData` (required so the ARM64 image finds your data)

Then:

```bash
docker compose build --no-cache
docker compose up -d
```

**Note:** The ARM64 image has no SSH and no env-based `serverconfig`; edit `./data/serverconfig.json` after the first start. The healthcheck may not run in the minimal runtime image (you can override or ignore).

---

## Updating the server

To switch to a newer Vintage Story version:

1. Set the version in your env (e.g. in `.env` or `.env.local`):
   ```bash
   VS_VERSION=1.21.7
   ```
2. Rebuild and recreate:
   ```bash
   docker compose build --no-cache
   docker compose up -d
   ```

Or use the script:

```bash
# Edit .env / .env.local with new VS_VERSION first, then:
./scripts/update.sh
```

---

## Port forwarding (router)

For players on the internet to connect, forward these ports from your **router** to the **host machine** that runs Docker:

| Port  | Protocol | Purpose        |
|-------|----------|----------------|
| 42420 | TCP      | Game (required) |
| 42420 | UDP      | Game (required) |
| 42421 | TCP      | SSH (only if you use `ENABLE_SSH=true`) |

Steps (conceptually):

1. Log in to your router’s admin page (e.g. 192.168.1.1).
2. Find “Port forwarding” / “Virtual server” / “NAT”.
3. Add a rule: external port **42420**, protocol **TCP**, internal IP = your PC’s LAN IP (e.g. 192.168.1.100), internal port **42420**.
4. Add another rule: external port **42420**, protocol **UDP**, same internal IP and port **42420**.
5. If you use SSH: external port **42421**, protocol **TCP**, internal IP same, internal port **42421** (Docker maps 42421→22 in the container).

Your public IP is what players use (e.g. `YOUR_PUBLIC_IP:42420`). Consider a dynamic DNS name if your public IP changes.

---

## Why SSH cannot share port 42420, and why 42421 is correct

- **42420** is the **game port**. The Vintage Story client talks a **custom game protocol** (TCP and UDP) on that port. It is not HTTP and not SSH.
- **SSH** uses **port 22** inside the container and its own protocol. You cannot run both the game server and SSH on the same port: each port can only have one listener.
- So we keep:
  - **42420** (TCP+UDP) for the game only.
  - **42421** on the host mapped to **22** in the container when you want SSH. That way game and SSH don’t conflict and you don’t expose the default SSH port 22 on the host.

---

## Security note (SSH)

If you set `ENABLE_SSH=true` and expose the host to the internet:

- **Use key-based SSH only**: disable password logins, use `AuthorizedKeysFile` and add your public key into the container (e.g. via a mounted `./data/.ssh/authorized_keys` or an image that sets it).
- **Firewall**: Only open **42421** (or 42420) if you need them; restrict source IPs if possible.
- Prefer **not** exposing SSH to the internet and use it only from your LAN, or use a VPN.

---

## Memory limit

- The compose file uses **`mem_limit: 1400m`** (1.4 GB). With plain **`docker compose`** (no Swarm), this is the option that is applied; **`deploy.resources.limits.memory`** is **not** applied by the default Docker Compose engine (it is for Docker Swarm).
- So for a normal home server, **`mem_limit`** is correct and is what we use.

---

## Data layout (bind mount)

Everything under `./data` is persistent:

- `./data/serverconfig.json` — server settings (created from `.env` on first run if missing).
- `./data/Saves/` — world saves.
- `./data/Mods/` — server mods (drop .zip here).
- `./data/Logs/` — server logs.

You can edit `serverconfig.json` or add mods directly on the host; restart the container for changes to take effect.

---

## Optional: first admin

Set `ADMIN_USER=YourPlayerName` in `.env` (or `.env.local`). On **first** run, if `serverconfig.json` is generated for you, the server will run `/op YourPlayerName` at startup so you get admin rights in-game. If you already have an existing `serverconfig.json`, add yourself via the in-game console or by adding `/op YourPlayerName` to the `StartupCommands` in `./data/serverconfig.json`.

---

## Optional: community image

If you prefer not to build from source, you can use the community image **lowerparchment/vintage_story_server** (e.g. tag `vanilla-1.21.6`) and mount `./data` to `/root/.config/VintagestoryData`. That image does **not** include SSH; this setup’s custom Dockerfile adds the server plus optional SSH in one container.
