# Orca headless server on Coolify

This deployment runs `orca serve` from the official Orca Linux AppImage. It is
multi-architecture (`amd64` and `arm64`), runs as an unprivileged user, and
persists both Orca's state and its repositories.

Remote Orca Servers are beta. Orca recommends keeping the server on a private
network path such as Tailscale, WireGuard, a trusted LAN, or an SSH tunnel. Do
not expose port `6768` directly to the public internet.

## Files

- `Dockerfile` downloads and extracts the official Orca release from
  `stablyai/orca` on GitHub.
- `compose.yaml` defines the service, private port binding, health check, and
  persistent volumes.
- `.env.example` documents every deployment setting.

The `orca-home` volume contains Orca settings, pairing grants, provider
credentials, and session state. The `orca-workspace` volume contains cloned
repositories and worktrees. Back up both volumes and protect them as secrets.

## Choose a private connection

Use one of these configurations before deploying.

### Tailscale or a trusted private LAN

Install and connect Tailscale on the **Coolify host** (not in this container),
then use the host's literal Tailscale IPv4 address for the Docker bind. The
pairing address may be either that IP or the host's Tailscale MagicDNS name:

```dotenv
ORCA_BIND_ADDRESS=100.64.1.20
ORCA_PAIRING_ADDRESS=your-server.your-tailnet.ts.net
```

`ORCA_BIND_ADDRESS` cannot be a hostname because Docker requires a host IP for
an interface-specific port mapping. Do not use `0.0.0.0` or the server's public
IP.

For a trusted LAN, use the host's private LAN IPv4 address instead. Allow TCP
port `6768` only from the intended private network in the host firewall and, if
applicable, in your Tailscale ACLs.

### SSH tunnel

Keep the defaults:

```dotenv
ORCA_BIND_ADDRESS=127.0.0.1
ORCA_PAIRING_ADDRESS=127.0.0.1
```

After deployment, keep this tunnel running on the computer with the Orca
desktop client:

```bash
ssh -N -L 6768:127.0.0.1:6768 user@your-coolify-host
```

The pairing URL printed by the server will then point at the locally forwarded
address.

## Deploy in Coolify

1. Push these files to a Git repository that Coolify can access.
2. In Coolify, create a **Docker Compose** resource from that repository.
3. Copy the variables from `.env.example` into Coolify's environment settings.
   Select one of the private connection configurations above. Pin
   `ORCA_VERSION` to a stable version for repeatable builds.
4. Do not assign a public Coolify domain to this service. The Compose port
   mapping is the intended connection path.
5. Deploy the resource and wait for the health check to pass.
6. Open the service logs and copy the `orca://...` runtime pairing URL printed
   by `orca serve`. Treat this URL like a password.
7. On your laptop, open Orca desktop and go to **Settings → Remote Orca
   Servers → Add Server**. Paste the pairing URL and connect.

If the server is rebuilt before you use the printed URL, copy the newest URL
from the current container logs.

## Provider accounts and agent CLIs

Provider authentication and coding-agent CLIs live on the server, not on the
desktop client. Open Coolify's terminal for the `orca` service and inspect or
add Orca-managed accounts:

```bash
orca account list
orca account add --agent codex
orca account add --agent claude
```

Codex device authorization can be completed in a browser on another computer.
Any extra tools required by your repositories or agents must also be installed
in the image. Add them to the `Dockerfile`; do not install system tools only in
a running container, because those changes disappear on redeploy. User-level
files under `/home/orca` persist.

## Local validation

```bash
cp .env.example .env
docker compose config --quiet
docker compose build
docker compose up -d
docker compose logs -f orca
```

With the default SSH-only binding, local Docker users can paste the printed
pairing URL directly into Orca desktop on the same machine.

## Updating Orca

Update `ORCA_VERSION` to a stable version from the official releases page and
redeploy. Keep the desktop client and server reasonably close in version;
Orca reports incompatible remote protocol versions when either side is too old.

## Troubleshooting

- **No pairing URL:** inspect the full startup logs and confirm the container is
  healthy. A new, unused pairing URL is generated after a restart.
- **Client remains disconnected:** verify `ORCA_PAIRING_ADDRESS` is reachable
  from the client and that `ORCA_BIND_ADDRESS` exists on the Coolify host.
- **Port allocation fails:** another process is using port `6768`, or the bind
  address is not assigned to the host. Change `ORCA_PORT` or correct the host
  address.
- **Agent CLI not found:** install that CLI in the image and authenticate it from
  the Coolify service terminal. The client laptop's `PATH` and credentials are
  not transferred to the server.
- **Permission errors after reusing volumes:** set `ORCA_UID` and `ORCA_GID` to
  the ownership expected by those volumes, then rebuild.

References: [Remote Orca Servers](https://www.onorca.dev/docs/remote-servers),
[Orca installation](https://www.onorca.dev/docs/install), and
[official releases](https://github.com/stablyai/orca/releases).
