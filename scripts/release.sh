#!/usr/bin/env bash
# scripts/release.sh - whisper-native release (adapted from fordaj/logamuffin's
# release.sh; same flow, Zig + CMake instead of a hand-written C++ build).
#
# Verifies the pinned upstream whisper.cpp submodule, cross-compiles the
# release executables via scripts/build.sh (Zig `zig c++` for the Linux and
# Windows targets, native clang++ for macOS), packs each platform into
# WhisperNative_<tag>_<platform>.tar.gz (.zip on Windows; flat archives:
# executables + README + LICENSE + upstream LICENSE + build metadata),
# generates SHA-256 checksums, tags HEAD, and publishes a GitHub release.
#
# Usage:
#   scripts/release.sh v0.1.0   # tag HEAD as v0.1.0, then build + release
#   scripts/release.sh --from-tag
#                               # HEAD must already be on tag vX.Y.Z
#                               # (used by CI on tag pushes); no tag is created
#   scripts/release.sh --dry-run [v0.1.0]
#                               # build + pack only; touches nothing remote
#
# Prerequisites: zig, cmake, git, tar, zip, and (for the real release) gh
# authenticated via `gh auth login`. The working tree must be clean; HEAD
# should be pushed.

set -euo pipefail

DRY_RUN=0
FROM_TAG=0
REQ_TAG=""

usage() {
    cat <<'EOF'
Usage: scripts/release.sh [--dry-run] [--from-tag] [vX.Y.Z]

Compute/verify the release tag, cross-compile via scripts/build.sh
(Zig + native clang) into build/release/<platform>/whisper-cli[.exe]
and whisper-server[.exe], stage each into dist/<platform>/ with
README.md, LICENSE, the upstream whisper.cpp LICENSE and a
WHISPER-NATIVE-BUILDINFO.txt, pack into
WhisperNative_<tag>_<platform>.tar.gz (.zip on Windows), create an
annotated tag (unless --from-tag), push it, and create a GitHub release
with the archives + SHA-256 checksums.

Flags:
  --dry-run, -n   Build + pack, but do not tag/push/release.
  --from-tag      HEAD must already be on a vX.Y.Z tag (CI tag pushes);
                  skips creating/pushing the tag.
  --help, -h      Show this help.

Env:
  BUILD_MODE   Passed through to scripts/build.sh (default: release).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
    --dry-run | -n)
        DRY_RUN=1
        shift
        ;;
    --from-tag)
        FROM_TAG=1
        shift
        ;;
    --help | -h)
        usage
        exit 0
        ;;
    v[0-9]*)
        REQ_TAG="$1"
        shift
        ;;
    *)
        echo "release.sh: unknown argument: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
done

log() { printf 'release.sh: %s\n' "$*"; }
die() {
    printf 'release.sh: error: %s\n' "$*" >&2
    exit 1
}
need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

for cmd in git zig cmake tar zip; do need_cmd "$cmd"; done

if [[ "$DRY_RUN" -ne 1 ]]; then
    need_cmd gh
    if ! gh auth status >/dev/null 2>&1; then
        die "gh is not authenticated (run: gh auth login)"
    fi
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
SCRIPT_DIR="$REPO_ROOT/scripts"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/entry.sh"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
HEAD_SHORT="$(git rev-parse --short HEAD)"
log "repo: $REPO_ROOT"
log "branch: $BRANCH  HEAD: $HEAD_SHORT"
if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY RUN: no tag/push/release will happen"
fi

# --- Resolve TAG -------------------------------------------------------
if [[ -n "$REQ_TAG" ]]; then
    TAG="$REQ_TAG"
    if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        die "tag looks invalid: '$TAG' (expected vX.Y.Z)"
    fi
    if [[ "$FROM_TAG" -eq 1 ]]; then
        die "--from-tag and an explicit tag are mutually exclusive"
    fi
elif [[ "$FROM_TAG" -eq 1 ]]; then
    TAG="$(git describe --tags --exact-match --match 'v[0-9]*' HEAD 2>/dev/null)" \
        || die "--from-tag given but HEAD is not on a vX.Y.Z tag"
    if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        die "--from-tag: tag '$TAG' does not match vX.Y.Z"
    fi
else
    die "no tag given. Pass an explicit tag (e.g. scripts/release.sh v0.1.0) or --from-tag in CI."
fi
VERSION="${TAG#v}"
log "VERSION=$VERSION  TAG=$TAG"

# --- Precondition: clean working tree ---------------------------------
if [[ -n "$(git status --porcelain)" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "warning: working tree is not clean (allowed in --dry-run)"
        git status --short | sed 's/^/release.sh:   /' >&2
    else
        die "working tree is not clean (commit or stash first):"$'\n'"$(git status --short)"
    fi
fi

# Best-effort fetch so remote tag-existence checks are current.
if ! git fetch origin --tags 2>/dev/null; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "warning: git fetch origin --tags failed; remote tag check may be stale"
    else
        die "git fetch origin --tags failed"
    fi
fi

# --- Tag must not already exist ----------------------------------------
if [[ "$FROM_TAG" -eq 0 ]]; then
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
        die "tag $TAG already exists locally"
    fi
    if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
        die "tag $TAG already exists on origin"
    fi
fi

# --- Verify pinned upstream submodule -----------------------------------
UPSTREAM_HEAD="$(git -C "$WHISPER_CPP_DIR" rev-parse HEAD 2>/dev/null)" \
    || die "upstream submodule not initialized — run: git submodule update --init $WHISPER_CPP_DIR"
[[ "$UPSTREAM_HEAD" == "$WHISPER_CPP_COMMIT" ]] || die "upstream submodule at $UPSTREAM_HEAD, expected $WHISPER_CPP_COMMIT ($WHISPER_CPP_VERSION)"
log "upstream: whisper.cpp $WHISPER_CPP_VERSION ($UPSTREAM_HEAD)"

# --- Cross-compile release executables ----------------------------------
log "cross-compiling release executables (TAG=$TAG) via scripts/build.sh..."
BUILD_MODE="${BUILD_MODE:-release}" bash "$REPO_ROOT/scripts/build.sh"

shopt -s nullglob
build_dirs=(build/release/*/)
((${#build_dirs[@]} > 0)) || die "scripts/build.sh produced no build/release/<platform>/ directories"
log "built ${#build_dirs[@]} platform directories:"
for d in "${build_dirs[@]}"; do log "  $d"; done

# --- Stage dist/<platform>/ ---------------------------------------------
# Flat layout: executables + README.md + LICENSE + upstream LICENSE +
# build metadata at the archive root. Model weights are NOT included;
# download them separately (see README.md).
log "staging dist/..."
rm -rf -- dist
mkdir -p -- dist
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
GIT_COMMIT="$(git rev-parse HEAD)"
for d in "${build_dirs[@]}"; do
    platform="$(basename "$d")"
    mkdir -p "dist/$platform"
    staged=0
    for exe in $WHISPER_EXECUTABLES; do
        for cand in "$d/$exe" "$d/$exe.exe"; do
            if [[ -f "$cand" ]]; then
                cp -p "$cand" "dist/$platform/"
                staged=$((staged + 1))
            fi
        done
    done
    ((staged > 0)) || die "no executables found in $d"
    for doc in README.md LICENSE "$WHISPER_CPP_DIR/LICENSE"; do
        [[ -f "$doc" ]] || die "missing $doc (needed for release archives)"
    done
    cp -p README.md LICENSE "dist/$platform/"
    cp -p "$WHISPER_CPP_DIR/LICENSE" "dist/$platform/LICENSE.whisper.cpp"
    cat >"dist/$platform/WHISPER-NATIVE-BUILDINFO.txt" <<EOF
whisper-native: $PROJECT_NAME
whisper-native version: $TAG
whisper-native source: $PROJECT_URL (commit $GIT_COMMIT)
upstream whisper.cpp: $WHISPER_CPP_VERSION ($WHISPER_CPP_COMMIT)
upstream url: $WHISPER_CPP_URL
platform: $platform
executables: $WHISPER_EXECUTABLES
build type: release (CPU-only, generic baseline, no GPU backends)
build date (UTC): $BUILD_DATE
license: MIT (this project); upstream whisper.cpp: MIT (LICENSE.whisper.cpp)
models: not included; see README.md ("Downloading models")
EOF
done

# Native binary should run (guards the packaging wiring).
case "$(uname -s):$(uname -m)" in
Darwin:x86_64) HOST_PLATFORM=macos-x86_64 ;;
Darwin:arm64) HOST_PLATFORM=macos-arm64 ;;
Linux:x86_64) HOST_PLATFORM=linux-x86_64 ;;
Linux:aarch64) HOST_PLATFORM=linux-arm64 ;;
MINGW*:x86_64 | MSYS*:x86_64 | CYGWIN*:x86_64) HOST_PLATFORM=windows-x86_64 ;;
*) HOST_PLATFORM="" ;;
esac
if [[ -n "$HOST_PLATFORM" && -x "dist/$HOST_PLATFORM/whisper-cli" ]]; then
    log "native smoke test: dist/$HOST_PLATFORM/whisper-cli --help"
    "dist/$HOST_PLATFORM/whisper-cli" --help >/dev/null || die "native binary failed --help"
fi

# --- Pack platform-native archives --------------------------------------
log "packing platform-native archives..."
archives=()
for d in dist/*/; do
    platform="$(basename "$d")"
    [[ -n "$platform" ]] || continue
    case "$platform" in
    windows-*)
        archive="dist/WhisperNative_${TAG}_${platform}.zip"
        rm -f "$archive"
        (cd "$d" && zip -q -j "../WhisperNative_${TAG}_${platform}.zip" ./*)
        ;;
    *)
        archive="dist/WhisperNative_${TAG}_${platform}.tar.gz"
        rm -f "$archive"
        (cd "$d" && tar -czf "../WhisperNative_${TAG}_${platform}.tar.gz" *)
        ;;
    esac
    [[ -s "$archive" ]] || die "failed to create $archive"
    log "  $archive:"
    case "$archive" in
    *.zip) unzip -l "$archive" | sed 's/^/release.sh:     /' ;;
    *) tar -tzf "$archive" | sed 's/^/release.sh:     /' ;;
    esac
    archives+=("$archive")
done

# --- Checksums -----------------------------------------------------------
log "generating checksums..."
if command -v shasum >/dev/null 2>&1; then
    (cd dist && shasum -a 256 WhisperNative_* >checksums.txt)
elif command -v sha256sum >/dev/null 2>&1; then
    (cd dist && sha256sum WhisperNative_* >checksums.txt)
else
    die "neither shasum nor sha256sum found (need one for checksums)"
fi
cat dist/checksums.txt | sed 's/^/release.sh:   /'

# --- Tag + GitHub release -----------------------------------------------
if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY RUN: would run:"
    log "  git tag -a $TAG -m \"whisper-native $TAG\""
    log "  git push origin $TAG"
    log "  gh release create $TAG --title \"whisper-native $TAG\" --generate-notes dist/WhisperNative_* dist/checksums.txt"
    log "dry run complete: VERSION=$VERSION TAG=$TAG"
    exit 0
fi

if [[ "$FROM_TAG" -eq 0 ]]; then
    log "creating annotated tag $TAG..."
    git tag -a "$TAG" -m "whisper-native $TAG"

    log "pushing tag $TAG..."
    git push origin "$TAG"
fi

if gh release view "$TAG" >/dev/null 2>&1; then
    die "GitHub release $TAG already exists (upload assets manually with: gh release upload $TAG dist/WhisperNative_* dist/checksums.txt --clobber)"
fi

log "creating GitHub release $TAG with ${#archives[@]} archives + checksums..."
gh release create "$TAG" \
    --title "whisper-native $TAG" \
    --generate-notes \
    "${archives[@]}" dist/checksums.txt

if REPO_SLUG="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" && [[ -n "$REPO_SLUG" ]]; then
    log "release: https://github.com/$REPO_SLUG/releases/tag/$TAG"
else
    log "release $TAG created (see GitHub Releases)"
fi
