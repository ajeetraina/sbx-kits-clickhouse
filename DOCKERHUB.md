# ClickHouse connector kit for Docker Sandboxes

A standalone [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) kit
(`kind: mixin`) that connects an agent to a **remote ClickHouse** warehouse
(ClickHouse Cloud or self-hosted) through the official
[ClickHouse MCP server](https://github.com/ClickHouse/mcp-clickhouse).

Source and full docs: https://github.com/ajeetraina/sbx-kits-clickhouse

## Why this is a good fit for sbx

ClickHouse is most useful pointed at real data, and that's exactly where the
sandbox model pays off: the agent can explore your warehouse while (a) it can
only reach the one host you allow-list, and (b) it never sees the password — the
sbx proxy holds it and injects it on the wire. Queries run over the HTTP
interface so the password is injected by the proxy and never lives inside the
container.

## Quick start

Set the password once with sbx (never on the command line), edit the
`CLICKHOUSE_*` values for your warehouse, then run:

    sbx secret set -g clickhouse
    sbx run --kit docker.io/ajeetraina777/sbx-clickhouse-kits:latest claude

The tag holds no secret. The sbx proxy injects the password from the stored
secret on outbound Basic auth to your warehouse host, so the key never enters
the sandbox. `sbx run` has no `-e` flag by design.

## How it works

The kit installs `mcp-clickhouse` and registers it with the Claude agent. It
connects over the HTTP interface (8443 for Cloud, 8123 for plain HTTP) using
`clickhouse-connect`. `CLICKHOUSE_PASSWORD` is set to the sentinel
`proxy-managed` inside the sandbox; the proxy recognizes the allow-listed host +
`scheme: basic` and swaps the sentinel for your real password on the outbound
request. The native protocol (port 9000/9440) is not wired up — its auth cannot
be proxy-injected.

Configuration values, validation details, and the raw `spec.yaml` live on
GitHub: https://github.com/ajeetraina/sbx-kits-clickhouse
