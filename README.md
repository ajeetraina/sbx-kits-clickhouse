# ClickHouse mixin (remote connector)

Connects an agent's Docker Sandbox to a **remote ClickHouse** warehouse
(ClickHouse Cloud or self-hosted) over the **HTTP interface**. The agent queries
your real warehouse with `curl` — inside an isolated microVM, under a `deny-all`
network policy, with the password injected by the sbx proxy so it **never enters
the container**.

![Architecture](assets/architecture.svg)

## Why this is a good fit for sbx

ClickHouse is most useful pointed at real data, and that's exactly where the
sandbox model pays off: the agent can explore your warehouse while (a) it can
only reach the one host you allow-list, and (b) it never sees the password — the
proxy holds it and injects it on the wire.

## How the credential stays out of the container

1. `CLICKHOUSE_PASSWORD` is set to the sentinel `proxy-managed` inside the sandbox.
2. The agent calls the ClickHouse HTTP interface with two headers:
   `X-ClickHouse-User: <user>` and `X-ClickHouse-Key: proxy-managed`.
3. The proxy recognizes the allow-listed host and swaps the sentinel in the
   `X-ClickHouse-Key` header for your real password on the outbound request.

The ClickHouse **native** protocol (port 9000/9440) is raw TCP and cannot be
injected this way — so this kit drives ClickHouse over the **HTTP interface**
(8443 for Cloud, 8123 for plain HTTP).

> **Why header auth, not HTTP Basic?** ClickHouse's HTTP interface also accepts
> `Authorization: Basic base64(user:pass)`, but the sbx v0.39.0 proxy's
> `scheme: basic` injection does not rewrite the base64-encoded Basic header — the
> sentinel would leak through unswapped and auth would fail. The
> `X-ClickHouse-User` / `X-ClickHouse-Key` headers carry the credential in plain
> form, so the proxy's header sentinel-swap works cleanly. (This also means the
> `clickhouse-connect`-based [MCP server](https://github.com/ClickHouse/mcp-clickhouse),
> which authenticates via Basic auth, is **not** wired up by this kit.)

## Configure

**1. Set the connection target** with the helper — it rewrites every place the
host must match (it lives in **3** spots) and re-validates, so nothing can drift:

```bash
scripts/set-host.sh <your-host>.clickhouse.cloud
# with options:
scripts/set-host.sh ch.internal.example.com --user analyst --port 8123 --secure false
```

These are all non-secret values (defaults shown); the helper edits them in
[`spec.yaml`](./spec.yaml):

| value | default | meaning |
|-------|---------|---------|
| `CLICKHOUSE_HOST` | `CHANGE_ME.clickhouse.cloud` | your HTTP(S) host, no scheme/port |
| `CLICKHOUSE_PORT` | `8443` | `8443` Cloud HTTPS · `8123` plain HTTP |
| `CLICKHOUSE_USER` | `default` | ClickHouse username |
| `CLICKHOUSE_DATABASE` | `default` | default database |
| `CLICKHOUSE_SECURE` | `true` | `true` for TLS/Cloud, `false` for plain HTTP |

> In this v0.39.0 grammar there's no `args` templating, so these are plain
> literals that must stay in sync — `set-host.sh` is the single source of truth
> so they can't diverge (a drift the validator won't catch but the engine
> rejects at run time).

**2. Set the password** (never stored in the kit):

```bash
sbx secret set clickhouse        # prompts for the value; stored in your secret store
```

The first `sbx run` (or `sbx create`) prompts to authorize sending the
`clickhouse` credential to your host and writes the binding into
`~/.config/sbx/credentials.yaml` for you. Approve it once; the host must match
`CLICKHOUSE_HOST` / the inject domain / the network allow entry.

## Usage

Published OCI artifact:

```bash
sbx run claude --kit docker.io/ajeetraina777/clickhouse-kit:latest .
```

From a pinned git ref:

```bash
sbx run claude --kit "git+https://github.com/ajeetraina/sbx-kits-clickhouse.git#ref=<40-hex-sha>" .
```

Local path (while authoring):

```bash
sbx run claude --kit . .
```

## Verify

```bash
sbx kit validate .
sbx kit inspect  .                             # confirm host resolved into inject + allow

# End to end
sbx create claude --kit . --name ch-probe .

# the password is injected into X-ClickHouse-Key; the container only holds the sentinel
sbx exec ch-probe -- sh -c 'curl -sk \
  -H "X-ClickHouse-User: $CLICKHOUSE_USER" -H "X-ClickHouse-Key: $CLICKHOUSE_PASSWORD" \
  "https://$CLICKHOUSE_HOST:$CLICKHOUSE_PORT/?query=SELECT%201"'      # -> 1
sbx exec ch-probe -- sh -c 'curl -sk \
  -H "X-ClickHouse-User: $CLICKHOUSE_USER" -H "X-ClickHouse-Key: $CLICKHOUSE_PASSWORD" \
  "https://$CLICKHOUSE_HOST:$CLICKHOUSE_PORT/?query=SHOW%20DATABASES"'  # -> your databases

# then ask the agent: "run SELECT count() FROM system.tables against ClickHouse"
sbx rm --force ch-probe
```

## Notes & limitations

- **HTTP interface only.** No `clickhouse-client` (native protocol) — its auth
  can't be proxy-injected. The agent queries via `curl` to the HTTP interface,
  where the `X-ClickHouse-Key` header is injected by the proxy.
- **No MCP server.** The `clickhouse-connect`-based
  [`mcp-clickhouse`](https://github.com/ClickHouse/mcp-clickhouse) server
  authenticates with HTTP Basic auth, which the sbx v0.39.0 proxy does not
  inject correctly (the base64 Basic header isn't rewritten), so it is not wired
  up. If a future sbx fixes `scheme: basic` injection, the MCP server can be
  added back for structured tools.
- **TLS.** Pass `curl -k`: the proxy terminates TLS inside the container with its
  own CA. The proxy→warehouse hop is still TLS-verified, so the connection to
  ClickHouse stays protected.
- **Read-only.** Keep to `SELECT` / `SHOW` / `DESCRIBE`. For a hard guarantee,
  use a read-only ClickHouse user or append `&readonly=1` to the query URL.
- **Cloud port.** Confirm your proxy policy permits HTTPS CONNECT to `:8443`
  (not just `:443`). If queries hang, check that first.
- **Agent-agnostic.** No agent-specific setup — any agent that can run `curl`
  works (Claude, Codex, Gemini, …).

## Publishing

This repo publishes the kit to Docker Hub as an OCI artifact via
[`scripts/push-kits.sh`](scripts/push-kits.sh) (and the
[`Publish Kit`](.github/workflows/push-kits.yaml) workflow on push to `main`):

```bash
DOCKERHUB_NAMESPACE=ajeetraina777 TAG=latest bash scripts/push-kits.sh
```

The workflow needs `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` repo secrets.

## License

MIT — see [LICENSE](LICENSE).
