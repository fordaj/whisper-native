#!/usr/bin/env bash
# scripts/build.sh — cross-compile whisper.cpp executables for the six
# release targets (CPU-only, generic baselines, no GPU backends).
#
# Builds the executables listed in WHISPER_EXECUTABLES
# (scripts/.common.env) from the pinned upstream whisper.cpp submodule
# (third_party/whisper.cpp), using upstream's CMake configuration —
# no source files are listed or patched here.
#
# macOS targets use the native clang/clang++ driving CMake
# (-arch x86_64 / arm64); the four Linux/Windows targets cross-compile
# with Zig (`zig cc`/`zig c++`) via the toolchain files in
# cmake/toolchains/. Linux targets are static musl builds.
#
# Usage:
#   BUILD_MODE=release scripts/build.sh   # default
#   BUILD_MODE=debug   scripts/build.sh
#   CLEAN_BUILD=false  scripts/build.sh   # reuse cmake build dirs
#   TARGETS="linux-x86_64 macos-arm64" scripts/build.sh   # subset
#
# Outputs: build/<mode>/<platform>/<executable>[.exe]

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/entry.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/upstream.sh"

# ============================================================
# Configuration
# ============================================================

BUILD_MODE="${BUILD_MODE:-release}"
case "$BUILD_MODE" in
release) CMAKE_BUILD_TYPE=Release ;;
debug) CMAKE_BUILD_TYPE=Debug ;;
*)
    log ERROR "invalid BUILD_MODE='$BUILD_MODE' (use release or debug)"
    exit 2
    ;;
esac

CLEAN_BUILD="${CLEAN_BUILD:-true}"

# Optional subset of targets: space-separated platform names.
ALL_TARGETS="macos-x86_64 macos-arm64 windows-x86_64 windows-arm64 linux-x86_64 linux-arm64"
TARGETS="${TARGETS:-$ALL_TARGETS}"

BUILD_ROOT="build/$BUILD_MODE"

echo "============================================================"
echo " whisper-native build"
echo "============================================================"
echo "Mode:      $BUILD_MODE (CMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE)"
echo "Targets:   $TARGETS"
echo "Clean:     $CLEAN_BUILD"
echo "Upstream:  whisper.cpp $WHISPER_CPP_VERSION ($WHISPER_CPP_COMMIT)"
echo "============================================================"
echo

# ============================================================
# Verify the pinned upstream submodule
# ============================================================
verify_upstream

# ============================================================
# Common CMake configuration (CPU-only, generic baselines)
#
# GGML_NATIVE is OFF everywhere so no -march=native or host-specific
# code paths leak into release artifacts. The per-ISA options are
# pinned OFF for the same reason; the result is a plain baseline build
# (x86-64 SSE2 on Intel/AMD, armv8 baseline on ARM64) on every target.
# All GPU/acceleration backends are disabled. BUILD_SHARED_LIBS=OFF
# keeps every executable self-contained (no bundled runtime libraries).
# ============================================================
COMMON_CMAKE_ARGS=(
    "-DCMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE"
    # Zig embeds debug info in default release compiles; keep release
    # artifacts free of it (objects are otherwise optimized).
    -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG -g0"
    -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG -g0"

    -DGGML_NATIVE=OFF
    -DGGML_SSE42=OFF
    -DGGML_AVX=OFF
    -DGGML_AVX2=OFF
    -DGGML_AVX512=OFF
    -DGGML_FMA=OFF
    -DGGML_F16C=OFF
    -DGGML_BMI2=OFF
    -DGGML_ACCELERATE=OFF
    -DGGML_OPENMP=OFF
    -DGGML_CCACHE=OFF
    -DGGML_CUDA=OFF
    -DGGML_HIP=OFF
    -DGGML_VULKAN=OFF
    -DGGML_METAL=OFF
    -DGGML_OPENCL=OFF
    -DWHISPER_COREML=OFF
    -DWHISPER_CURL=OFF
    -DWHISPER_SDL2=OFF
    -DWHISPER_BUILD_TESTS=OFF
    -DWHISPER_BUILD_EXAMPLES=ON
    -DWHISPER_BUILD_SERVER=ON
    -DWHISPER_BUILD_IS_DEV=OFF
    -DBUILD_SHARED_LIBS=OFF
)

# ============================================================
# Build helper
# ============================================================
build_target() {
    local name="$1"
    local platform="$2"
    shift 2
    local -a extra_cmake_args=("$@")

    local output_dir="$BUILD_ROOT/$platform"
    local work_dir="$output_dir/work"

    echo "------------------------------------------------------------"
    echo "Building: $name"
    echo "Output:   $output_dir"
    echo "------------------------------------------------------------"

    if [[ "$CLEAN_BUILD" == "true" ]]; then
        rm -rf -- "$output_dir"
    fi
    mkdir -p -- "$work_dir"

    cmake -S "$WHISPER_CPP_DIR" -B "$work_dir" \
        "${COMMON_CMAKE_ARGS[@]}" \
        "${extra_cmake_args[@]}"

    local -a targets=()
    for exe in $WHISPER_EXECUTABLES; do
        targets+=("$exe")
    done
    cmake --build "$work_dir" --config "$CMAKE_BUILD_TYPE" --parallel \
        --target "${targets[@]}"

    # Flat output layout: build/<mode>/<platform>/<executable>[.exe]
    local exe
    for exe in $WHISPER_EXECUTABLES; do
        local found=""
        for cand in "$work_dir/bin/$exe" "$work_dir/bin/$exe.exe"; do
            if [[ -f "$cand" ]]; then
                found="$cand"
                break
            fi
        done
        if [[ -z "$found" ]]; then
            log ERROR "expected executable not found: $work_dir/bin/$exe[.exe]"
            exit 1
        fi
        cp -p "$found" "$output_dir/$(basename "$found")"
    done

    echo "SUCCESS: $name"
    echo
}

# ============================================================
# Targets
# ============================================================
for target in $TARGETS; do
    case "$target" in
    macos-x86_64)
        build_target "macOS Intel x86-64" "macos-x86_64" \
            -DCMAKE_OSX_ARCHITECTURES=x86_64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
        ;;
    macos-arm64)
        build_target "macOS Apple Silicon ARM64" "macos-arm64" \
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0
        ;;
    windows-x86_64)
        build_target "Windows x86-64 (MinGW via Zig)" "windows-x86_64" \
            -DCMAKE_TOOLCHAIN_FILE="$REPO_ROOT/cmake/toolchains/zig-windows-x86_64.cmake"
        ;;
    windows-arm64)
        build_target "Windows ARM64 (MinGW via Zig)" "windows-arm64" \
            -DCMAKE_TOOLCHAIN_FILE="$REPO_ROOT/cmake/toolchains/zig-windows-arm64.cmake"
        ;;
    linux-x86_64)
        build_target "Linux x86-64 (musl, static, via Zig)" "linux-x86_64" \
            -DCMAKE_TOOLCHAIN_FILE="$REPO_ROOT/cmake/toolchains/zig-linux-x86_64.cmake"
        ;;
    linux-arm64)
        build_target "Linux ARM64 (musl, static, via Zig)" "linux-arm64" \
            -DCMAKE_TOOLCHAIN_FILE="$REPO_ROOT/cmake/toolchains/zig-linux-arm64.cmake"
        ;;
    *)
        log ERROR "unknown target: $target (known: $ALL_TARGETS)"
        exit 2
        ;;
    esac
done

# ============================================================
# Summary
# ============================================================
echo "============================================================"
echo " Build complete!"
echo "============================================================"
for target in $TARGETS; do
    find "$BUILD_ROOT/$target" -maxdepth 1 -type f -print | sort
done
echo
