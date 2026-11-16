#!/usr/bin/env bash
# scripts/test_models.sh — smoke-test a built whisper-cli against real
# models downloaded from the upstream Hugging Face repo.
#
# Tests one English-only model (tiny.en) and one multilingual model
# (tiny), as required to validate the release distribution. Both run the
# jfk.wav sample bundled in the upstream submodule and check that a
# non-empty transcription is produced containing the word "country".
#
# Usage:
#   scripts/test_models.sh                 # test host-platform binary
#   WHISPER_CLI=/path/to/whisper-cli scripts/test_models.sh
#   WHISPER_MODELS_DIR=/path/to/models scripts/test_models.sh
#
# Models are cached in build/models/ (git-ignored) and re-downloaded
# only when missing.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/entry.sh"

MODELS_DIR="${WHISPER_MODELS_DIR:-$REPO_ROOT/build/models}"
SAMPLE="${WHISPER_SAMPLE:-$REPO_ROOT/$WHISPER_CPP_DIR/samples/jfk.wav}"
HF_BASE="https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

# --- Locate the binary --------------------------------------------------
if [[ -z "${WHISPER_CLI:-}" ]]; then
    case "$(uname -s):$(uname -m)" in
    Darwin:x86_64) HOST=macos-x86_64 ;;
    Darwin:arm64) HOST=macos-arm64 ;;
    Linux:x86_64) HOST=linux-x86_64 ;;
    Linux:aarch64) HOST=linux-arm64 ;;
    MINGW*:x86_64 | MSYS*:x86_64 | CYGWIN*:x86_64) HOST=windows-x86_64 ;;
    *)
        log ERROR "unsupported host; set WHISPER_CLI explicitly"
        exit 2
        ;;
    esac
    SUFFIX=""
    case "$HOST" in
    windows-*) SUFFIX=".exe" ;;
    esac
    WHISPER_CLI="$REPO_ROOT/build/release/$HOST/whisper-cli$SUFFIX"
fi

[[ -x "$WHISPER_CLI" ]] || {
    log ERROR "whisper-cli not found or not executable: $WHISPER_CLI"
    log ERROR "build first (scripts/build.sh) or set WHISPER_CLI"
    exit 1
}
[[ -f "$SAMPLE" ]] || {
    log ERROR "sample not found: $SAMPLE (submodule initialized? git submodule update --init)"
    exit 1
}

mkdir -p "$MODELS_DIR"

download_model() {
    local name="$1"
    local dest="$MODELS_DIR/ggml-$name.bin"
    if [[ -f "$dest" ]]; then
        log INFO "model cached: $dest"
        return 0
    fi
    log INFO "downloading ggml-$name.bin (from $HF_BASE)..."
    curl -fsSL --retry 3 -o "$dest.tmp" "$HF_BASE/ggml-$name.bin"
    mv "$dest.tmp" "$dest"
    log INFO "downloaded: $dest"
}

run_model() {
    local name="$1"
    local expected_lang_flag="${2:-auto}"
    local model="$MODELS_DIR/ggml-$name.bin"
    log INFO "=== $name ($expected_lang_flag) ==="
    local out
    if [[ "$expected_lang_flag" == "auto" ]]; then
        out="$("$WHISPER_CLI" -m "$model" -f "$SAMPLE" -nt 2>&1)"
    else
        out="$("$WHISPER_CLI" -m "$model" -f "$SAMPLE" -nt -l en 2>&1)"
    fi
    printf '%s\n' "$out"
    local transcript
    transcript="$(printf '%s\n' "$out" | tr 'A-Z' 'a-z')"
    [[ -n "$(printf '%s' "$out" | tr -d '[:space:]')" ]] || {
        log ERROR "empty transcription from $name"
        exit 1
    }
    if ! grep -q "country" <<<"$transcript"; then
        log ERROR "transcription from $name does not contain 'country': $out"
        exit 1
    fi
    log INFO "OK: $name"
}

download_model tiny.en
download_model tiny

run_model tiny.en en
run_model tiny auto

log INFO "all model smoke tests passed ($WHISPER_CLI)"
