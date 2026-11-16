# AGENTS.md

Guidance for agents (and humans) working in this repository.

## What this is

whisper-native packages [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
as precompiled, CPU-only native binaries (`whisper-cli`, `whisper-server`)
for six desktop/server targets. It is a thin, pinned build/release layer —
no upstream sources are forked or patched.

## Ground rules

- **Do not rewrite the build system.** Adapted from fordaj/logamuffin:
  Zig cross-compilation (`scripts/build.sh`, `cmake/toolchains/zig-*.cmake`
  plus `cmake/wrappers/zig-*`), native clang++ on macOS, environment cascade
  (`scripts/env.sh` + `scripts/.common.env` + `scripts/.<platform>.env`),
  platform-specific output dirs (`build/<mode>/<platform>/`), release
  packaging (`scripts/release.sh`), git-tag versioning (`scripts/version.sh`).
- **Upstream is a pinned submodule** (`third_party/whisper.cpp`). Never edit
  files inside it; bump the gitlink + `WHISPER_CPP_VERSION`/`WHISPER_CPP_COMMIT`
  in `scripts/.common.env` together. `scripts/build.sh` and `release.sh`
  fail if the checkout doesn't match the pin.
- **Release builds are CPU-only and generic.** Keep `GGML_NATIVE=OFF` and all
  per-ISA options OFF; never introduce `-march=native` or GPU backends into
  the release matrix. Experimental backends belong in user-side CMake flags
  only (documented in README.md).
- **Model weights are never bundled** into this repo or into archives.
  `scripts/test_models.sh` downloads tiny/tiny.en on demand.
- **macOS uses native clang** (`-arch x86_64` / `arm64`); the other four
  targets cross-compile with `zig cc`/`zig c++` (musl static on Linux).
- **No `$buildhost` specifics in artifacts.** CMake files under
  `cmake/toolchains/` are the only per-target customization; executables
  come from upstream's CMake targets (`WHISPER_EXECUTABLES` in
  `scripts/.common.env`).

## Commands

```bash
git submodule update --init third_party/whisper.cpp   # required once
scripts/build.sh                                      # six targets, release
BUILD_MODE=debug TARGETS="macos-arm64" scripts/build.sh
scripts/test_models.sh                                # English + multilingual smoke test
scripts/release.sh --dry-run                          # build + pack, nothing remote
scripts/version.sh                                    # TAG=/VERSION= from git tags
```

## Done means

- `scripts/build.sh` succeeds for all six targets.
- `scripts/test_models.sh` passes on the host (English-only + multilingual).
- Archives contain executables, `README.md`, `LICENSE`,
  `LICENSE.whisper.cpp`, `WHISPER-NATIVE-BUILDINFO.txt`, and are listed in
  `checksums.txt`.
