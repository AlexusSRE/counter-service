# Vintage Story dedicated server with optional SSH
# Version configurable via build-arg VS_VERSION (default: 1.21.6)
FROM debian:bookworm-slim

ARG VS_VERSION=1.21.6
ENV VS_VERSION=${VS_VERSION} \
    VS_DATA=/home/vintagestory/data \
    VS_SERVER=/opt/vintagestory

# Install dependencies: .NET 8 runtime, SSH, and tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    libc6 \
    libgcc-s1 \
    libstdc++6 \
    openssh-server \
    procps \
    netcat-openbsd \
    tar \
    && curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel 8.0 --runtime dotnet --install-dir /usr/share/dotnet \
    && ln -s /usr/share/dotnet/dotnet /usr/bin/dotnet \
    && rm -rf /var/lib/apt/lists/*

ENV DOTNET_ROOT=/usr/share/dotnet

# Download and extract Vintage Story server from official CDN
# Tarball contains folder vs_server_linux-x64_<version>; move its contents into VS_SERVER.
RUN mkdir -p "${VS_SERVER}" /tmp/vs_extract \
    && curl -sSL "https://cdn.vintagestory.at/gamefiles/stable/vs_server_linux-x64_${VS_VERSION}.tar.gz" -o /tmp/vs_server.tar.gz \
    && tar -xzf /tmp/vs_server.tar.gz -C /tmp/vs_extract \
    && ( dir="/tmp/vs_extract/vs_server_linux-x64_${VS_VERSION}"; if [ -d "$dir" ]; then cp -a "$dir"/* "${VS_SERVER}/"; else cp -a /tmp/vs_extract/* "${VS_SERVER}/"; fi ) \
    && rm -rf /tmp/vs_extract /tmp/vs_server.tar.gz \
    && chmod +x "${VS_SERVER}/server.sh" 2>/dev/null || true

# Non-root user for running the server
RUN groupadd -r vintagestory -g 1000 \
    && useradd -r -u 1000 -g vintagestory -m -d /home/vintagestory vintagestory \
    && mkdir -p "${VS_DATA}" \
    && chown -R vintagestory:vintagestory "${VS_SERVER}" "${VS_DATA}"

# SSH: allow password auth only if ENABLE_SSH_PASSWORD is set; prefer key-based
RUN mkdir -p /run/sshd \
    && sed -i 's/#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Entrypoint runs as root so it can start sshd and set permissions, then runs server as vintagestory
WORKDIR ${VS_SERVER}

# Server data and config live here (mounted)
VOLUME ["/home/vintagestory/data"]

EXPOSE 42420/tcp 42420/udp
# Port 22 is used only when SSH is enabled (mapped to host 42421)

ENTRYPOINT ["/entrypoint.sh"]
