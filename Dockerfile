ARG ORCA_RELEASE_VERSION=1.4.177
ARG CODEX_VERSION=0.147.0

FROM node:24-bookworm-slim AS codex-release

ARG CODEX_VERSION

RUN npm install --global "@openai/codex@${CODEX_VERSION}" \
    && codex --version \
    && npm cache clean --force


FROM ubuntu:24.04 AS orca-release

ARG TARGETARCH
ARG ORCA_RELEASE_VERSION

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) asset="orca-linux.AppImage" ;; \
      arm64) asset="orca-linux-arm64.AppImage" ;; \
      *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    case "${ORCA_RELEASE_VERSION}" in \
      latest) release_path="latest/download" ;; \
      v*) release_path="download/${ORCA_RELEASE_VERSION}" ;; \
      *) release_path="download/v${ORCA_RELEASE_VERSION}" ;; \
    esac; \
    curl --fail --location --retry 5 --retry-all-errors \
      --output /tmp/orca.AppImage \
      "https://github.com/stablyai/orca/releases/${release_path}/${asset}"; \
    chmod 0755 /tmp/orca.AppImage; \
    cd /tmp; \
    ./orca.AppImage --appimage-extract; \
    mv /tmp/squashfs-root /opt/orca; \
    chmod -R a+rX /opt/orca; \
    test -x /opt/orca/AppRun; \
    test -f /opt/orca/resources/app.asar.unpacked/out/cli/index.js; \
    rm /tmp/orca.AppImage


FROM ubuntu:24.04

ARG ORCA_RELEASE_VERSION
ARG CODEX_VERSION

ENV DEBIAN_FRONTEND=noninteractive

# This matches Orca's official headless AppImage test environment, with Git,
# SSH, and tini added for production repository/agent use.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        dbus-x11 \
        git \
        jq \
        libasound2t64 \
        libatk-bridge2.0-0 \
        libatspi2.0-0 \
        libdrm2 \
        libgbm1 \
        libgtk-3-0 \
        libnss3 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxkbcommon0 \
        libxrandr2 \
        libxss1 \
        openssh-client \
        procps \
        tini \
        util-linux \
        xauth \
        xvfb \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=orca-release /opt/orca /opt/orca
COPY --from=codex-release /usr/local/bin/node /usr/local/bin/node
COPY --from=codex-release /usr/local/lib/node_modules/@openai/codex /usr/local/lib/node_modules/@openai/codex

RUN ln -s /usr/local/lib/node_modules/@openai/codex/bin/codex.js /usr/local/bin/codex \
    && codex --version

# Run the extracted AppImage entry point directly. Orca officially supports
# invoking AppRun with `serve` on headless Linux.
COPY --chmod=0755 <<'EOF' /usr/local/bin/orca
#!/usr/bin/env bash
set -euo pipefail
exec /opt/orca/AppRun "$@"
EOF

RUN set -eux; \
    orca_uid=1000; \
    orca_gid=1000; \
    if getent group "${orca_gid}" >/dev/null; then \
        existing_group="$(getent group "${orca_gid}" | cut -d: -f1)"; \
        if [ "${existing_group}" != orca ]; then \
            groupmod --new-name orca "${existing_group}"; \
        fi; \
    else \
        groupadd --gid "${orca_gid}" orca; \
    fi; \
    if getent passwd "${orca_uid}" >/dev/null; then \
        existing_user="$(getent passwd "${orca_uid}" | cut -d: -f1)"; \
        if [ "${existing_user}" != orca ]; then \
            usermod --login orca --home /home/orca \
                --shell /bin/bash --gid "${orca_gid}" "${existing_user}"; \
        else \
            usermod --home /home/orca --shell /bin/bash \
                --gid "${orca_gid}" orca; \
        fi; \
    else \
        useradd --uid "${orca_uid}" --gid "${orca_gid}" \
            --create-home --shell /bin/bash orca; \
    fi; \
    install -d -o orca -g orca \
        /home/orca \
        /home/orca/.cache \
        /home/orca/.config \
        /home/orca/.local \
        /home/orca/.local/bin \
        /workspace

ENV HOME=/home/orca \
    XDG_CACHE_HOME=/home/orca/.cache \
    XDG_CONFIG_HOME=/home/orca/.config \
    PATH=/home/orca/.local/bin:/usr/local/bin:/usr/bin:/bin \
    ORCA_APPIMAGE_NO_SANDBOX=1

LABEL org.opencontainers.image.title="Orca headless server" \
      org.opencontainers.image.description="Headless server using the official Orca Linux release" \
      org.opencontainers.image.source="https://github.com/stablyai/orca" \
      org.opencontainers.image.version="${ORCA_RELEASE_VERSION}"

USER orca
WORKDIR /workspace

EXPOSE 6768

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/bin/dbus-run-session", "--", "/usr/bin/xvfb-run", "-a", "/usr/local/bin/orca"]
CMD ["serve", "--port", "6768", "--pairing-address", "127.0.0.1"]
