#!/usr/bin/env bash
# Destructive/process-safety helpers for the LAN integration test.

# Prints "backed_up" when an existing path was moved, or "absent" when there
# was no pre-test state. An occupied backup destination is a hard failure and
# the live path is not touched.
jacgrid_backup_test_state() {
    local live="$1" saved="$2"

    if [ -e "$saved" ]; then
        echo "backup destination already exists: $saved" >&2
        return 1
    fi
    if [ ! -e "$live" ]; then
        printf '%s\n' absent
        return 0
    fi
    mkdir -p "$(dirname "$saved")"
    mv "$live" "$saved" || return 1
    printf '%s\n' backed_up
}

# Restores only state explicitly owned by the test:
#   untouched  backup never succeeded; do nothing
#   backed_up  remove test-created live state and restore the saved original
#   absent     remove the live state created by the test
jacgrid_restore_test_state() {
    local live="$1" saved="$2" mode="$3"

    case "$mode" in
        untouched)
            return 0
            ;;
        backed_up)
            # Never remove the live path unless the original backup is known
            # to exist and is ready to restore.
            if [ ! -e "$saved" ]; then
                echo "refusing restore: owned backup is missing: $saved" >&2
                return 1
            fi
            if [ -e "$live" ]; then
                rm -rf "$live"
            fi
            mkdir -p "$(dirname "$live")"
            mv "$saved" "$live"
            ;;
        absent)
            if [ -e "$live" ]; then
                rm -rf "$live"
            fi
            ;;
        *)
            echo "unknown test-state ownership mode: $mode" >&2
            return 2
            ;;
    esac
}

jacgrid_own_pid() {
    local wanted="$1" pid
    for pid in "${OWNED_PIDS[@]:-}"; do
        [ "$pid" = "$wanted" ] && return 0
    done
    OWNED_PIDS+=("$wanted")
}

jacgrid_forget_owned_pid() {
    local forgotten="$1" pid
    local -a kept=()
    for pid in "${OWNED_PIDS[@]:-}"; do
        [ "$pid" = "$forgotten" ] || kept+=("$pid")
    done
    OWNED_PIDS=("${kept[@]:-}")
}
