#!/usr/bin/env bash
#
# version.sh - print the version of the repository.
#
# whisper-native keeps version parity with upstream whisper.cpp: the
# project version IS the pinned upstream version (WHISPER_CPP_VERSION in
# scripts/.common.env). scripts/release.sh tags the release commit with
# that version, so a whisper-native release v1.9.5 builds upstream
# whisper.cpp v1.9.5.
#
# Usage:
#   scripts/version.sh                 # prints "TAG=<v>" and "VERSION=<v>"
#   scripts/version.sh --format text   # same as default
#   scripts/version.sh --format shell  # prints "export TAG=..." lines
#   scripts/version.sh --format json   # prints a small JSON document

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/entry.sh"

usage() {
    cat <<'EOF'
Usage: scripts/version.sh [--format text|shell|json]

Print the project version (parity with the pinned upstream whisper.cpp).

  text   TAG=<tag> and VERSION=<version> lines (default)
  shell  export TAG=... and export VERSION=... lines
  json   a small JSON document with tag/version/commit/dirty/upstream
EOF
}

FORMAT="text"
while [[ $# -gt 0 ]]; do
    case "$1" in
    --format)
        [[ $# -ge 2 ]] || {
            echo "version.sh: --format requires a value" >&2
            exit 2
        }
        FORMAT="$2"
        shift 2
        ;;
    --format=*)
        FORMAT="${1#--format=}"
        shift
        ;;
    --help | -h)
        usage
        exit 0
        ;;
    *)
        echo "version.sh: unknown argument: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
done

TAG="$WHISPER_CPP_VERSION"
VERSION="${TAG#v}"
COMMIT="$(git rev-parse --short HEAD)"
DIRTY="false"
if [[ -n "$(git status --porcelain)" ]]; then
    DIRTY="true"
fi

case "$FORMAT" in
text)
    printf 'TAG=%s\n' "$TAG"
    printf 'VERSION=%s\n' "$VERSION"
    ;;
shell)
    printf 'export TAG=%s\n' "$TAG"
    printf 'export VERSION=%s\n' "$VERSION"
    ;;
json)
    printf '{"tag":"%s","version":"%s","commit":"%s","dirty":%s,"upstream":"%s"}\n' \
        "$TAG" "$VERSION" "$COMMIT" "$DIRTY" "$WHISPER_CPP_VERSION"
    ;;
*)
    echo "version.sh: unknown format: $FORMAT (expected text, shell or json)" >&2
    exit 2
    ;;
esac
