#!/usr/bin/env bash
# scripts/upstream.sh — verify the pinned upstream whisper.cpp submodule.
#
# Sourced by scripts/build.sh and scripts/release.sh. Requires log()
# (from scripts/entry.sh) and the WHISPER_CPP_* variables (from
# scripts/.common.env).
#
# An uninitialized submodule is an *empty* directory and git happily
# walks up into the enclosing repository — so a bare
# `git -C <dir> rev-parse HEAD` reports the superproject's HEAD and
# hides the real problem. Detect the missing `.git` (file or directory)
# first.

# verify_upstream — exit 1 with an actionable message unless the
# submodule is initialized and checked out at the pinned commit.
verify_upstream() {
    local dir="${WHISPER_CPP_DIR:?upstream.sh: WHISPER_CPP_DIR not set}"

    if [[ ! -e "$dir/.git" ]]; then
        log ERROR "upstream submodule not initialized (empty or missing: $dir)"
        log ERROR "run: git submodule update --init $dir"
        exit 1
    fi

    local head
    if ! head="$(git -C "$dir" rev-parse HEAD 2>/dev/null)"; then
        log ERROR "upstream submodule is not a git repository: $dir"
        log ERROR "run: git submodule update --init $dir"
        exit 1
    fi

    if [[ "$head" != "$WHISPER_CPP_COMMIT" ]]; then
        log ERROR "upstream submodule at $head"
        log ERROR "this repository pins whisper.cpp $WHISPER_CPP_VERSION ($WHISPER_CPP_COMMIT)"
        log ERROR "run: git -C $dir checkout $WHISPER_CPP_COMMIT"
        exit 1
    fi
}
