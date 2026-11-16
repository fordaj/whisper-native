#!/usr/bin/env bash
#
# version.sh - print the version of the repository.
#
# The version is derived from git tags (pattern vX.Y.Z). When HEAD is
# exactly on a tag, that tag is the version; otherwise a describe-style
# suffix is appended (e.g. v0.1.0-3-gdeadbee, with +dirty when the tree
# is dirty). With no tags reachable, the version is 0.0.0-dev+<sha>.
#
# Usage:
#   scripts/version.sh                 # prints "VERSION=<v>" and "TAG=<t>"
#   scripts/version.sh --format text   # same as default
#   scripts/version.sh --format shell  # prints "export VERSION=..." lines
#   scripts/version.sh --format json   # prints a small JSON document

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

usage() {
    cat <<'EOF'
Usage: scripts/version.sh [--format text|shell|json]

Print the repository version derived from git tags.

  text   TAG=<tag> and VERSION=<version> lines (default)
  shell  export TAG=... and export VERSION=... lines
  json   a small JSON document with tag/version/commit/dirty
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

COMMIT="$(git rev-parse --short HEAD)"
DIRTY="false"
if [[ -n "$(git status --porcelain)" ]]; then
    DIRTY="true"
fi

EXACT_TAG="$(git describe --tags --exact-match --match 'v[0-9]*' HEAD 2>/dev/null || true)"
if [[ -n "$EXACT_TAG" ]]; then
    TAG="$EXACT_TAG"
    if [[ "$DIRTY" == "true" ]]; then
        TAG="${TAG}+dirty"
    fi
else
    DESC="$(git describe --tags --match 'v[0-9]*' --abbrev=7 HEAD 2>/dev/null || true)"
    if [[ -z "$DESC" ]]; then
        TAG="v0.0.0-dev+$COMMIT"
    else
        TAG="$DESC"
        if [[ "$DIRTY" == "true" ]]; then
            TAG="${TAG}+dirty"
        fi
    fi
fi
VERSION="${TAG#v}"

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
    printf '{"tag":"%s","version":"%s","commit":"%s","dirty":%s}\n' \
        "$TAG" "$VERSION" "$COMMIT" "$DIRTY"
    ;;
*)
    echo "version.sh: unknown format: $FORMAT (expected text, shell or json)" >&2
    exit 2
    ;;
esac
