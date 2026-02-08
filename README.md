# OneIM + OpenClaw Bootstrap (Windows VM)

This repo is a **repeatable bootstrap** for a freshly reset Windows VM.

Goals:
- Ensure required software is installed (via **winget** + **npm**).
- Configure OpenClaw CLI remote target (Gateway URL/token).
- Install and run the **OpenClaw headless node host as a Windows Service**.
- Create exec approvals so `system.run` works without interactive prompts.

> Assumptions
> - Gateway WS is always: `ws://145.14.157.230:18789`
> - You have a Gateway token (see below).

## Quick start

Open **PowerShell as Administrator** (recommended for installs), then:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

# 1) Install prerequisites + OpenClaw CLI
.\scripts\01-install-tools.ps1

# 2) Configure OpenClaw remote + install node service
.\scripts\02-setup-openclaw-node-service.ps1 -GatewayToken "<PASTE_TOKEN_HERE>" -DisplayName "IAMSERVER"

# 3) Verify
.\scripts\03-verify.ps1 -GatewayToken "<PASTE_TOKEN_HERE>" -NodeIdOrIp "185.64.245.52"
```

## Where to get the Gateway token

You have two options:

### Option A (recommended): **Rotate/set a known token** on the Gateway
On the Gateway host, set/rotate the token to a known value, then use that token here.
How you do this depends on how the Gateway is started (service/docker/manual).

### Option B: Read it from the Gateway host’s configuration / service env
Look for `OPENCLAW_GATEWAY_TOKEN` (or the `--token ...` argument) in the Gateway service definition.

## Notes

- Pairing approval: on a fresh VM, the node host will appear as **pending** on the Gateway.
  Approve it once:

```bash
openclaw nodes pending
openclaw nodes approve <requestId>
```

- Exec approvals are written to `~\.openclaw\exec-approvals.json` for the service user.

## Scripts

- `scripts/01-install-tools.ps1`
  - Checks winget
  - Installs Git, Node.js LTS, PowerShell 7, SQLCMD
  - Installs OpenClaw CLI via npm

- `scripts/02-setup-openclaw-node-service.ps1`
  - Writes exec approvals (defaults security=full)
  - Sets `gateway.mode=remote`, `gateway.remote.url/token`
  - Installs node host service (`openclaw node install ...`) and restarts it
  - Auto-resolves the active node id (via `openclaw devices list --json`) and writes it to: `~\.openclaw\nodeid.txt`

- `scripts/03-verify.ps1`
  - Prints node service status
  - Prints `openclaw nodes list/describe` using explicit `--url/--token`

- `scripts/04-debug-node.ps1`
  - Diagnostics when the scheduled task exits immediately or `system.run` stays approval-gated
  - Shows service user/profile, approvals file locations, task events
  - Can run `~\.openclaw\node.cmd` in foreground to capture the real error

- `scripts/05-generate-schemaextension.ps1`
  - Generates a SchemaExtension control XML from a JSON spec (see `specs/*.json`)

- `scripts/06-apply-schemaextension.ps1`
  - Runs `SchemaExtensionCmd.exe` with `/Conn`, `/Auth`, `/Definition`
