#!/bin/bash
# Bumps VERSION, builds, and pushes aabutouq/registry-secret-sync as vX.X.X.
#
# Usage:
#   ./build-and-push.sh [patch|minor|major]   (default: patch)
#   PUSH=0 ./build-and-push.sh                (build only, skip push)
#
# After a successful run, update registrySecretSync.image.tag in
# helm/ase-market/values.yaml and commit+push for ArgoCD to sync.
set -euo pipefail

IMAGE="aabutouq/registry-secret-sync"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$DIR/VERSION"
BUMP="${1:-patch}"
PUSH="${PUSH:-1}"

if [[ ! "$BUMP" =~ ^(patch|minor|major)$ ]]; then
    echo "Usage: $0 [patch|minor|major]" >&2
    exit 1
fi

if [[ ! -f "$VERSION_FILE" ]]; then
    echo "v0.0.0" > "$VERSION_FILE"
fi

current="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$current" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "VERSION file content '$current' doesn't match vX.X.X — refusing to proceed." >&2
    exit 1
fi

major_n="${BASH_REMATCH[1]}"
minor_n="${BASH_REMATCH[2]}"
patch_n="${BASH_REMATCH[3]}"

case "$BUMP" in
    patch) patch_n=$((patch_n + 1)) ;;
    minor) minor_n=$((minor_n + 1)); patch_n=0 ;;
    major) major_n=$((major_n + 1)); minor_n=0; patch_n=0 ;;
esac

new_version="v${major_n}.${minor_n}.${patch_n}"
tag="${IMAGE}:${new_version}"

echo "Bumping $current -> $new_version ($BUMP)"
echo "Building $tag ..."
docker build -t "$tag" "$DIR"

if [[ "$PUSH" == "1" ]]; then
    echo "Pushing $tag ..."
    docker push "$tag"
else
    echo "PUSH=0 set — skipping push."
fi

echo "$new_version" > "$VERSION_FILE"
echo
echo "Done: $tag"
echo "Next: bump registrySecretSync.image.tag to $new_version in helm/ase-market/values.yaml, then commit+push for ArgoCD to sync."
