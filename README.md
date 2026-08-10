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
- `.env.example` contains optional API-token variables for local development.

The `orca-home` volume contains Orca settings, pairing grants, provider
credentials, and session state. The `orca-workspace` volume contains cloned
repositories and worktrees. Back up both volumes and protect them as secrets.

## Choose a private connection

The checked-in Compose configuration is set up for this server's Tailscale
address, `100.83.19.5`.

### Tailscale or a trusted private LAN

Install and connect Tailscale on the **Coolify host** (not in this container).
For another server, change both occurrences of `100.83.19.5` in `compose.yaml`.
The Docker bind must remain a literal host IP. The pairing address may instead
be the host's Tailscale MagicDNS name:

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

### SSH tunnel alternative

To use an SSH tunnel instead, change both Compose addresses to `127.0.0.1`:

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
3. No Coolify environment variables are required for the default deployment;
   non-secret configuration is source-controlled in `Dockerfile` and
   `compose.yaml`.
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
desktop client. The image includes the Codex CLI version pinned by
`CODEX_VERSION` in the `Dockerfile`. Open Coolify's terminal for the running
`orca` service and add an Orca-managed Codex account:

```bash
codex --version
orca account add --agent codex
orca account list
```

The account command starts Codex device authorization. Open the displayed URL
on any computer, enter the displayed code, and return to the terminal after the
login completes. Orca imports the account into its managed account store under
the persistent `/home/orca` volume.

Any extra tools required by repositories or other agents must also be installed
in the image. Add them to the `Dockerfile`; do not install system tools only in
a running container, because those changes disappear on redeploy. User-level
files under `/home/orca` persist.

## Local validation

```bash
docker compose config --quiet
docker compose build
docker compose up -d
docker compose logs -f orca
```

Copy `.env.example` to `.env` first only when testing optional API tokens
locally. Never commit the resulting `.env` file.

## Updating Orca

Update `ORCA_RELEASE_VERSION` at the top of `Dockerfile` to a stable version
from the official releases page and redeploy. Keep the desktop client and
server reasonably close in version; Orca reports incompatible remote protocol
versions when either side is too old.

## Troubleshooting

- **No pairing URL:** inspect the full startup logs and confirm the container is
  healthy. A new, unused pairing URL is generated after a restart.
- **Client remains disconnected:** verify the pairing address in `compose.yaml`
  is reachable and that its port-bind IP exists on the Coolify host.
- **Port allocation fails:** another process is using port `6768`, or the bind
  address is not assigned to the host. Change the port or host address in
  `compose.yaml`.
- **Agent CLI not found:** install that CLI in the image and authenticate it from
  the Coolify service terminal. The client laptop's `PATH` and credentials are
  not transferred to the server.
- **Permission errors after reusing volumes:** align `orca_uid` and `orca_gid`
  in `Dockerfile` with the ownership expected by those volumes, then rebuild.

References: [Remote Orca Servers](https://www.onorca.dev/docs/remote-servers),
[Orca installation](https://www.onorca.dev/docs/install), and
[official releases](https://github.com/stablyai/orca/releases).
