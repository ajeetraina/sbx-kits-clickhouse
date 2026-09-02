#!/usr/bin/env bash
set -euo pipefail

# push-kits.sh — validate and publish the ClickHouse kit to Docker Hub as an OCI
# artifact, the same way the sbx partner kits are published (`sbx kit push`).
#
# Target namespace defaults to `sbx` (hub.docker.com/u/sbx). Override for testing
# in your own namespace:
#   DOCKERHUB_NAMESPACE=<you> TAG=dev bash scripts/push-kits.sh
#
# Consumers then run:
#   sbx run claude --kit docker.io/<namespace>/clickhouse-kit:<tag> .

namespace="${DOCKERHUB_NAMESPACE:-${DOCKER_NAMESPACE:-ajeetraina777}}"
tag="${TAG:-latest}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
image="docker.io/$namespace/clickhouse-kit"

# publish SPEC_DIR IMAGE_TAG README_FILE
# Stages the kit (spec.yaml + README + LICENSE), validates it, and pushes one tag.
publish() {
  local spec_dir="$1" image_tag="$2" readme="$3"
  local stage
  stage="$(mktemp -d /tmp/clickhouse-kit-push.XXXXXX)"
  mkdir -p "$stage/clickhouse"
  cp "$spec_dir/spec.yaml" "$stage/clickhouse/spec.yaml"
  cp "$readme"             "$stage/clickhouse/README.md"
  cp "$repo_root/LICENSE"  "$stage/clickhouse/LICENSE"
  sbx kit validate "$stage/clickhouse"
  sbx kit push     "$stage/clickhouse" "$image:$image_tag"
  rm -rf "$stage"
  echo "Pushed $image:$image_tag"
}

# Single kind: mixin kit at the repo root -> :$tag (default :latest).
publish "$repo_root" "$tag" "$repo_root/README.md"
