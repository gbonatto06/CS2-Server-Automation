#!/usr/bin/env bash
# Verify that all Docker image tags in a compose file exist on their registry.
set -euo pipefail

COMPOSE_FILE="${1:?Usage: $0 <docker-compose.yml>}"
FAILED=0

check_tag() {
  local image="$1"
  local name tag

  # Split image:tag
  name="${image%%:*}"
  tag="${image##*:}"
  if [[ "$tag" == "$name" ]]; then
    tag="latest"
  fi

  # Add library/ prefix for official images (no slash in name)
  local repo="$name"
  if [[ "$repo" != */* ]]; then
    repo="library/$repo"
  fi

  # Get anonymous auth token
  local token
  token=$(curl -sf "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" \
    | jq -r '.token')

  # Check manifest exists
  local status
  status=$(curl -so /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    -H "Accept: application/vnd.oci.image.index.v1+json" \
    "https://registry-1.docker.io/v2/${repo}/manifests/${tag}")

  if [[ "$status" == "200" ]]; then
    echo "OK: ${image}"
  else
    echo "FAIL: ${image} (HTTP ${status})"
    FAILED=1
  fi
}

# Extract image references from compose file
images=$(grep -oP '^\s*image:\s*\K\S+' "$COMPOSE_FILE" | sort -u)

for img in $images; do
  check_tag "$img"
done

if [[ "$FAILED" -ne 0 ]]; then
  echo "::error::One or more Docker image tags do not exist!"
  exit 1
fi

echo "All Docker image tags verified."
