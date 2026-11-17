#!/usr/bin/env bash
# scripts/release.sh - whisper-native release (adapted from fordaj/logamuffin's
# release.sh; same flow, Zig + CMake instead of a hand-written C++ build).
#
# whisper-native keeps version parity with upstream whisper.cpp: the
# release tag IS the pinned upstream version (WHISPER_CPP_VERSION in
# scripts/.common.env). "scripts/release.sh" therefore needs no version
# argument — it tags HEAD with e.g. v1.9.5, builds, packages, pushes the
# tag, and publishes the GitHub release. Pushing a vX.Y.Z tag also
# triggers the GitHub Actions release workflow (.github/workflows/ci.yml,
# "release" job) which rebuilds on the self-hosted macOS runner and
# publishes the release if it does not already exist.
#
# Usage:
#   scripts/release.sh              # tag HEAD as WHISPER_CPP_VERSION (e.g.
#                                   # v1.9.5), build, pack, push tag, release
#   scripts/release.sh --from-tag   # HEAD must already be on the pinned tag
#                                   # (used by CI on tag pushes); no tag is created
#   scripts/release.sh --dry-run    # build + pack only; touches nothing remote
#
# Prerequisites: zig, cmake, git, tar, zip, and (for the real release) gh
# authenticated via `gh auth login`. The working tree must be clean; HEAD
# should be pushed.

set -euo pipefail

DRY_RUN=0
FROM_TAG=0

usage() {
    cat <<'EOF'
Usage: scripts/release.sh [--dry-run] [--from-tag]

Release whisper-native at the version pinned in scripts/.common.env
(WHISPER_CPP_VERSION, e.g. v1.9.5 — parity with upstream whisper.cpp):

  1. verifies the pinned upstream submodule and the clean tree,
  2. cross-compiles via scripts/build.sh (Zig + native clang) into
     build/release/<platform>/whisper-cli[.exe] and whisper-server[.exe],
  3. stages each platform into dist/<platform>/ (executables + README.md +
     LICENSE + the upstream whisper.cpp LICENSE + WHISPER-NATIVE-BUILDINFO.txt),
  4. packs WhisperNative_<tag>_<platform>.tar.gz (.zip on Windows) and
     dist/checksums.txt,
  5. creates an annotated tag on HEAD (unless --from-tag), pushes it, and
     creates the GitHub release with the archives + checksums
     (idempotent: an existing release is left untouched).

Flags:
  --dry-run, -n   Build + pack, but do not tag/push/release.
  --from-tag      HEAD must already be on the pinned tag (CI tag pushes);
                  skips creating/pushing the tag.
  --help, -h      Show this help.

Env:
  BUILD_MODE   Passed through to scripts/build.sh (default: release).

The tag tracks the pinned upstream version and can only be released once:
to re-release the same upstream version, delete the tag and the GitHub
release first, or update the pin in scripts/.common.env (see README.md,
"Updating the upstream whisper.cpp version").
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

# --- Resolve TAG (parity with the pinned upstream whisper.cpp) ---------
TAG="$WHISPER_CPP_VERSION"
VERSION="${TAG#v}"
if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "WHISPER_CPP_VERSION '$TAG' does not match vX.Y.Z — fix scripts/.common.env"
fi
if [[ "$FROM_TAG" -eq 1 ]]; then
    HEAD_TAG="$(git describe --tags --exact-match --match 'v[0-9]*' HEAD 2>/dev/null)" \
        || die "--from-tag given but HEAD is not on a tag"
    [[ "$HEAD_TAG" == "$TAG" ]] || die "--from-tag: HEAD is on '$HEAD_TAG', expected pinned tag '$TAG'"
fi
log "VERSION=$VERSION  TAG=$TAG (parity with upstream $WHISPER_CPP_VERSION)"

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
if [[ "$FROM_TAG" -eq 0 && "$DRY_RUN" -ne 1 ]]; then
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
        die "tag $TAG already exists locally. whisper-native releases track the pinned upstream version;"$'\n'"      delete the tag (and the GitHub release) to re-release it, or update the pin in scripts/.common.env first."
    fi
    if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
        die "tag $TAG already exists on origin. whisper-native releases track the pinned upstream version;"$'\n'"      delete the tag (and the GitHub release) to re-release it, or update the pin in scripts/.common.env first."
    fi
fi

# --- Fail fast if the release already exists ---------------------------
# parity: one release per pinned upstream version. In --from-tag mode
# (CI on tag pushes) an existing release means the release was created
# elsewhere (e.g. locally via scripts/release.sh) — no-op cleanly.
if [[ "$DRY_RUN" -ne 1 ]] && gh release view "$TAG" >/dev/null 2>&1; then
    if [[ "$FROM_TAG" -eq 1 ]]; then
        log "GitHub release $TAG already exists; nothing to do"
        exit 0
    else
        die "GitHub release $TAG already exists (tag absent)."$'\n'"      Update the pin in scripts/.common.env or delete the release first."
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
    git tag -a "$TAG" -m "whisper-native $TAG (whisper.cpp $WHISPER_CPP_VERSION)"

    log "pushing tag $TAG..."
    git push origin "$TAG"
fi

# Idempotency: if the release already exists (e.g. created from another
# machine or a previous run), keep it — do not re-upload or overwrite.
if gh release view "$TAG" >/dev/null 2>&1; then
    log "GitHub release $TAG already exists; leaving it untouched (assets not re-uploaded)"
    exit 0
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
