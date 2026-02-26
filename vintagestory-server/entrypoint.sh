#!/bin/bash
set -e

DATA_PATH="${VS_DATA:-/home/vintagestory/data}"
SERVER_DIR="${VS_SERVER:-/opt/vintagestory}"
CONFIG_FILE="${DATA_PATH}/serverconfig.json"

# Generate serverconfig.json from environment if it doesn't exist.
# Must include Roles and DefaultRoleCode (e.g. "suplayer") or server will refuse to start.
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "Generating serverconfig.json from environment..."
    mkdir -p "${DATA_PATH}"
    STARTUP_CMDS=""
    if [ -n "${ADMIN_USER}" ]; then
        STARTUP_CMDS="/op ${ADMIN_USER}"
    fi
    PASSWORD_JSON="null"
    [ -n "${VS_PASSWORD}" ] && PASSWORD_JSON="\"${VS_PASSWORD}\""
    cat > "${CONFIG_FILE}" << 'ROLESEOF'
{
  "ServerName": "Vintage Story Server",
  "Password": null,
  "MaxClients": 8,
  "Public": false,
  "AdvertiseServer": false,
  "Port": 42420,
  "WelcomeMessage": "Welcome!",
  "StartupCommands": "",
  "DefaultRoleCode": "suplayer",
  "Roles": [
    {"Code": "suvisitor", "PrivilegeLevel": -1, "Name": "Survival Visitor", "Privileges": ["chat"], "DefaultGameMode": 1, "Color": "Green", "LandClaimAllowance": 0, "LandClaimMinSize": {"X": 5, "Y": 5, "Z": 5}, "LandClaimMaxAreas": 3, "AutoGrant": false},
    {"Code": "suplayer", "PrivilegeLevel": 0, "Name": "Survival Player", "Privileges": ["controlplayergroups", "manageplayergroups", "chat", "areamodify", "build", "useblock", "attackcreatures", "attackplayers", "selfkill"], "DefaultGameMode": 1, "Color": "White", "LandClaimAllowance": 262144, "LandClaimMinSize": {"X": 5, "Y": 5, "Z": 5}, "LandClaimMaxAreas": 3, "AutoGrant": false},
    {"Code": "admin", "PrivilegeLevel": 99999, "Name": "Admin", "Privileges": ["build", "useblock", "buildblockseverywhere", "useblockseverywhere", "kick", "ban", "whitelist", "announce", "controlserver", "grantrevoke", "root", "selfkill"], "DefaultGameMode": 1, "Color": "LightBlue", "LandClaimAllowance": 2147483647, "LandClaimMinSize": {"X": 5, "Y": 5, "Z": 5}, "LandClaimMaxAreas": 99999, "AutoGrant": true}
  ]
}
ROLESEOF
    # Override with env (sed to keep JSON valid)
    sed -i "s/\"Vintage Story Server\"/\"${VS_SERVER_NAME:-Vintage Story Server}\"/" "${CONFIG_FILE}"
    sed -i "s/\"Password\": null/\"Password\": ${PASSWORD_JSON}/" "${CONFIG_FILE}"
    sed -i "s/\"MaxClients\": 8/\"MaxClients\": ${VS_MAX_PLAYERS:-8}/" "${CONFIG_FILE}"
    sed -i "s/\"Public\": false/\"Public\": ${VS_PUBLIC:-false}/" "${CONFIG_FILE}"
    sed -i "s/\"AdvertiseServer\": false/\"AdvertiseServer\": ${VS_ADVERTISE:-false}/" "${CONFIG_FILE}"
    sed -i "s/\"Welcome!\"/\"${VS_WELCOME_MESSAGE:-Welcome!}\"/" "${CONFIG_FILE}"
    # StartupCommands may contain spaces/slashes; use # delimiter
    sed -i "s#\"StartupCommands\": \"\"#\"StartupCommands\": \"${STARTUP_CMDS}\"#" "${CONFIG_FILE}"
    chown vintagestory:vintagestory "${CONFIG_FILE}" 2>/dev/null || true
fi

# Optional: start SSH daemon (host maps 42421 -> 22)
if [ "${ENABLE_SSH}" = "true" ] || [ "${ENABLE_SSH}" = "1" ]; then
    echo "Starting SSH daemon on port 22 (map host 42421 -> 22)..."
    /usr/sbin/sshd
fi

# Run the server in foreground (as vintagestory user). runuser uses $HOME as CWD,
# so we must run inside a shell that cd's to SERVER_DIR.
# ARM64 experimental build may provide native ./VintagestoryServer; else use dotnet VintagestoryServer.dll.
exec runuser -u vintagestory -- env DOTNET_ROOT="${DOTNET_ROOT:-/usr/share/dotnet}" \
    bash -c "cd \"${SERVER_DIR}\" && if [ -x ./VintagestoryServer ]; then exec ./VintagestoryServer --dataPath \"${DATA_PATH}\"; else exec dotnet VintagestoryServer.dll --dataPath \"${DATA_PATH}\"; fi"
