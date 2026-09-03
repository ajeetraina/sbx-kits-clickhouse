# ClickHouse kit for Docker Sandboxes

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) kit (`kind: mixin`)
that connects an agent to a **remote ClickHouse** warehouse (ClickHouse Cloud or
self-hosted) over the **HTTP interface**. The agent queries your real warehouse
with `curl` — inside an isolated microVM, under a `deny-all` network policy, with
the password injected by the sbx proxy so it **never enters the container**.

Source and full docs: https://github.com/ajeetraina/sbx-kits-clickhouse

## How the credential stays out of the container

1. `CLICKHOUSE_PASSWORD` is set to the sentinel `proxy-managed` inside the sandbox.
2. The agent calls the HTTP interface with `X-ClickHouse-User: <user>` and
   `X-ClickHouse-Key: proxy-managed` headers.
3. The sbx proxy recognizes the allow-listed host and swaps the sentinel in the
   `X-ClickHouse-Key` header for your real password on the outbound request.

The ClickHouse **native** protocol (9000/9440) is raw TCP and can't be injected,
so this kit drives ClickHouse over the **HTTP interface** (8443 Cloud / 8123 plain).
Header auth is used rather than HTTP Basic because the sbx v0.39.0 proxy does not
rewrite the base64-encoded Basic header (so the `clickhouse-connect`-based MCP
server is not wired up).

## Quick start

Set the target host once (keeps the three in-spec copies in sync), store the
password as a secret, then run Claude with the kit:

    # from a clone of the repo
    scripts/set-host.sh <your-host>.clickhouse.cloud
    sbx secret set clickhouse

    sbx run claude --kit docker.io/ajeetraina777/clickhouse-kit:latest .

Then ask the agent: *"run SELECT count() FROM system.tables against ClickHouse"*.
The proxy injects the password on the wire; `sbx run` has no `-e` flag by design —
the key never enters the sandbox.

## Configuration

All non-secret; edit in `spec.yaml` (or via `scripts/set-host.sh`):

| value | default | meaning |
|-------|---------|---------|
| `CLICKHOUSE_HOST` | `CHANGE_ME.clickhouse.cloud` | your HTTP(S) host, no scheme/port |
| `CLICKHOUSE_PORT` | `8443` | `8443` Cloud HTTPS · `8123` plain HTTP |
| `CLICKHOUSE_USER` | `default` | ClickHouse username |
| `CLICKHOUSE_DATABASE` | `default` | default database |
| `CLICKHOUSE_SECURE` | `true` | `true` for TLS/Cloud, `false` for plain HTTP |

Full setup, limitations, and the raw `spec.yaml` live on GitHub:
https://github.com/ajeetraina/sbx-kits-clickhouse
