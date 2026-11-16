#!/usr/bin/env bash
# tools/runner-spawner/update.sh — refresh the bundled runner-spawner
# binaries from fordaj/runner-spawner releases (pinned by RUNNER_SPAWNER_TAG,
# default v0.0.1.2.6). Verifies the release checksums before installing.
#
# Usage:
#   tools/runner-spawner/update.sh              # download + install pinned version
#   tools/runner-spawner/update.sh --dry-run    # resolve + verify only

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"

RUNNER_SPAWNER_TOOL_REPO="${RUNNER_SPAWNER_TOOL_REPO:-fordaj/runner-spawner}"
RUNNER_SPAWNER_TAG="${RUNNER_SPAWNER_TAG:-v0.0.1.2.6}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

log() { printf 'update.sh: %s\n' "$*"; }
die() { printf 'update.sh: error: %s\n' "$*" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

log "downloading $RUNNER_SPAWNER_TOOL_REPO $RUNNER_SPAWNER_TAG..."
gh release download --repo "$RUNNER_SPAWNER_TOOL_REPO" "$RUNNER_SPAWNER_TAG" --dir "$TMP"
shasum -a 256 -c checksums.txt || sha256sum -c checksums.txt

if [[ "$DRY_RUN" -eq 1 ]]; then
    log "dry-run: checksums verified; nothing installed"
    exit 0
fi

declare -a PAIRS=(darwin-amd64:macos-x86_64 darwin-arm64:macos-arm64
    linux-amd64:linux-x86_64 linux-arm64:linux-arm64
    windows-amd64:windows-x86_64 windows-arm64:windows-arm64)

dest="$REPO_ROOT/tools/runner-spawner/$RUNNER_SPAWNER_TAG"
for pair in "${PAIRS[@]}"; do
    plat="${pair%%:*}"
    dir="${pair##*:}"
    d="$dest/$dir"
    rm -rf "$d"
    mkdir -p "$d"
    case "$plat" in
    windows-*) unzip -q -o "RunnerSpawner_${RUNNER_SPAWNER_TAG}_${plat}.zip" -d "$d" ;;
    *) tar -xzf "RunnerSpawner_${RUNNER_SPAWNER_TAG}_${plat}.tar.gz" -C "$d" ;;
    esac
    chmod +x "$d"/runner-spawner* 2>/dev/null || true
    log "installed: tools/runner-spawner/$RUNNER_SPAWNER_TAG/$dir"
done

log "done. Update RUNNER_SPAWNER_VERSION_DIR in scripts/.common.env when bumping the pin."
