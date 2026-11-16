#!/usr/bin/env bash
# scripts/entry.sh — shared entry point for whisper-native scripts.
#
# Sourced (never executed) by the task scripts. Sources scripts/env.sh
# (the environment cascade) and defines log(), a small stderr/stdout
# logger with the same call shape as the fordaj logging helper:
#
#   log INFO "message"
#
# INFO-and-below goes to stdout, WARNING-and-above goes to stderr.

set -euo pipefail

# _level_to_value <name-or-number> prints the numeric severity:
# words map through the built-in table (unknown names -> INFO=20),
# numbers pass through unchanged.
_level_to_value() {
    local name="$1"
    if [[ "$name" =~ ^-?[0-9]+$ ]]; then
        printf '%s' "$name"
        return 0
    fi
    local upper
    upper="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
    case "$upper" in
    TRACE) printf 5 ;;
    DEBUG) printf 10 ;;
    INFO) printf 20 ;;
    WARNING | WARN) printf 30 ;;
    ERROR) printf 40 ;;
    CRITICAL | FATAL) printf 50 ;;
    ALWAYS) printf -- -1 ;;
    *) printf 20 ;;
    esac
}

ENTRY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ENTRY_DIR/env.sh"

# log LEVEL [MESSAGE ...]
log() {
    if (($# == 0)); then
        printf 'log: usage: log LEVEL MESSAGE...\n' >&2
        return 2
    fi
    local level_arg="$1"
    shift
    local msg="$*"
    local level_value
    level_value="$(_level_to_value "$level_arg")"
    if [[ "$level_value" -ge 40 ]]; then
        printf '%s: [%s] %s\n' "${0:-log}" "$level_arg" "$msg" >&2
    else
        printf '%s: [%s] %s\n' "${0:-log}" "$level_arg" "$msg"
    fi
    return 0
}
