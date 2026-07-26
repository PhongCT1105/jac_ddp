#!/usr/bin/env bash
# Shared, side-effect-free helpers for JacGrid demo launchers and LAN tests.

jacgrid_valid_ipv4() {
    local ip="$1" octet
    local -a octets

    IFS=. read -r -a octets <<<"$ip"
    [ "${#octets[@]}" -eq 4 ] || return 1
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
        [ "$((10#$octet))" -le 255 ] || return 1
    done
    [ "${octets[0]}" -ne 0 ] || return 1
    [ "${octets[0]}" -ne 127 ] || return 1
}

jacgrid_interface_ipv4() {
    local iface="$1" ip=""

    if command -v ipconfig >/dev/null 2>&1; then
        ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    fi
    if [ -z "$ip" ] && command -v ifconfig >/dev/null 2>&1; then
        ip="$(ifconfig "$iface" 2>/dev/null \
            | awk '/inet / && $2 != "127.0.0.1" {print $2; exit}' || true)"
    fi
    if [ -z "$ip" ] && command -v ip >/dev/null 2>&1; then
        ip="$(ip -4 -o addr show dev "$iface" scope global 2>/dev/null \
            | awk '{sub(/\\/.*/, "", $4); print $4; exit}' || true)"
    fi
    if [ -n "$ip" ] && jacgrid_valid_ipv4 "$ip"; then
        printf '%s\n' "$ip"
        return 0
    fi
    return 1
}

jacgrid_ip_is_local() {
    local wanted="$1"

    if command -v ifconfig >/dev/null 2>&1 \
        && ifconfig 2>/dev/null \
            | awk '/inet / {print $2}' \
            | grep -Fqx "$wanted"; then
        return 0
    fi
    if command -v ip >/dev/null 2>&1 \
        && ip -4 -o addr show 2>/dev/null \
            | awk '{sub(/\\/.*/, "", $4); print $4}' \
            | grep -Fqx "$wanted"; then
        return 0
    fi
    return 1
}

jacgrid_physical_interface() {
    case "$1" in
        en[0-9]*|eth[0-9]*|wlan[0-9]*|wl[a-z0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}

jacgrid_default_interface() {
    local iface=""

    if command -v route >/dev/null 2>&1; then
        iface="$(route -n get default 2>/dev/null \
            | awk '/interface:/{print $2; exit}' || true)"
    fi
    if [ -z "$iface" ] && command -v ip >/dev/null 2>&1; then
        iface="$(ip route show default 2>/dev/null \
            | awk '/default/ {for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}' \
            || true)"
    fi
    [ -n "$iface" ] || return 1
    printf '%s\n' "$iface"
}

jacgrid_choose_lan_ip() {
    local override="${JACGRID_LAN_IP:-}" default_iface="" iface="" ip=""
    local -a candidates=()

    if [ -n "$override" ]; then
        if ! jacgrid_valid_ipv4 "$override"; then
            echo "ERROR: JACGRID_LAN_IP must be a non-loopback IPv4 address (got '$override')." >&2
            return 2
        fi
        if ! jacgrid_ip_is_local "$override"; then
            echo "ERROR: JACGRID_LAN_IP '$override' is not assigned to this machine." >&2
            return 2
        fi
        printf '%s\n' "$override"
        return 0
    fi

    default_iface="$(jacgrid_default_interface || true)"
    if [ -n "$default_iface" ] && jacgrid_physical_interface "$default_iface"; then
        ip="$(jacgrid_interface_ipv4 "$default_iface" || true)"
        if [ -n "$ip" ]; then
            printf '%s\n' "$ip"
            return 0
        fi
    fi

    # A VPN can own the default route (utun/tun/tap). In that case select an
    # active physical Wi-Fi/Ethernet interface, never the VPN address.
    if command -v ifconfig >/dev/null 2>&1; then
        while IFS= read -r iface; do
            jacgrid_physical_interface "$iface" || continue
            candidates+=("$iface")
        done < <(ifconfig -l 2>/dev/null | tr ' ' '\n')
    elif command -v ip >/dev/null 2>&1; then
        while IFS= read -r iface; do
            jacgrid_physical_interface "$iface" || continue
            candidates+=("$iface")
        done < <(ip -o link show 2>/dev/null \
            | awk -F': ' '{sub(/@.*/, "", $2); print $2}')
    fi

    for iface in "${candidates[@]}"; do
        [ "$iface" != "$default_iface" ] || continue
        ip="$(jacgrid_interface_ipv4 "$iface" || true)"
        if [ -n "$ip" ]; then
            printf '%s\n' "$ip"
            return 0
        fi
    done

    echo "ERROR: could not find an active physical/default-interface IPv4 address." >&2
    echo "Set JACGRID_LAN_IP to an IPv4 address assigned to this Mac." >&2
    return 1
}

jacgrid_pid_is_descendant() {
    local child="$1" ancestor="$2" current="$1" parent="" hops=0

    while [ -n "$current" ] && [ "$current" -gt 0 ] 2>/dev/null; do
        [ "$current" = "$ancestor" ] && return 0
        parent="$(ps -o ppid= -p "$current" 2>/dev/null | tr -d ' ' || true)"
        [ -n "$parent" ] || return 1
        [ "$parent" != "$current" ] || return 1
        current="$parent"
        hops=$((hops + 1))
        [ "$hops" -lt 128 ] || return 1
    done
    return 1
}

# Prints a listener PID only when lsof's current listener belongs to the
# supplied launcher process tree. It is side-effect-free: on a bind race it
# returns non-zero without printing or signaling the foreign listener.
jacgrid_listener_pid_for_owner() {
    local port="$1" owner_pid="$2" pid="" found=0

    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        found=1
        if jacgrid_pid_is_descendant "$pid" "$owner_pid"; then
            printf '%s\n' "$pid"
            return 0
        fi
    done < <(lsof -nP -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)

    if [ "$found" -eq 1 ]; then
        echo "listener on port $port is not owned by launcher PID $owner_pid" >&2
        return 2
    fi
    echo "no listener found on port $port" >&2
    return 1
}
