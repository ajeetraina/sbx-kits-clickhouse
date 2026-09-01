#!/usr/bin/env bash
set -euo pipefail

# Publishes the ClickHouse mixin as an OCI kit artifact to Docker Hub, matching
# the sbx-kits convention: docker.io/<namespace>/sbx-clickhouse-kits:<tag>.
#
# This kit is a single mixin (spec.yaml + README at the repo root), so there are
# no per-provider tags — just one artifact. Staging into a temp dir keeps the
# pushed kit to spec.yaml + README + LICENSE, nothing else from the repo.

namespace="${DOCKERHUB_NAMESPACE:-${DOCKER_NAMESPACE:-ajeetraina777}}"
tag="${TAG:-latest}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="docker.io/$namespace/sbx-clickhouse-kits"

stage="$(mktemp -d /tmp/clickhouse-kit-push.XXXXXX)"
mkdir -p "$stage/clickhouse"
cp "$repo_root/spec.yaml" "$stage/clickhouse/spec.yaml"
cp "$repo_root/README.md" "$stage/clickhouse/README.md"
cp "$repo_root/LICENSE"   "$stage/clickhouse/LICENSE"

sbx kit validate "$stage/clickhouse"
sbx kit push "$stage/clickhouse" "$image:$tag"
rm -rf "$stage"
echo "Pushed $image:$tag"
