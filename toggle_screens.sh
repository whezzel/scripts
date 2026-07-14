#!/usr/bin/env bash
set -euo pipefail

# ================== CONFIGURATION ==================
KVM="HDMI-A-1"
PHYS1="DP-1"
PHYS2="DP-3"

# Physical layout (change if your resolutions/positions change)
PHYS1_POS="0,0"
PHYS2_POS="3440,280"
# ==================================================

# Environment setup for KDE shortcuts
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] || { [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; }; then
    PID=$(pgrep -u "$USER" plasmashell | head -n1)
    if [ -n "$PID" ]; then
        ENVIRON=$(tr '\0' '\n' < "/proc/$PID/environ")
        export DBUS_SESSION_BUS_ADDRESS=$(echo "$ENVIRON" | grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)
        [ -n "${DISPLAY:-}" ] || export DISPLAY=$(echo "$ENVIRON" | grep '^DISPLAY=' | cut -d= -f2-)
        [ -n "${WAYLAND_DISPLAY:-}" ] || export WAYLAND_DISPLAY=$(echo "$ENVIRON" | grep '^WAYLAND_DISPLAY=' | cut -d= -f2-)
        [ -n "${XAUTHORITY:-}" ] || export XAUTHORITY=$(echo "$ENVIRON" | grep '^XAUTHORITY=' | cut -d= -f2-)
    else
        echo "Error: Could not find plasmashell process" >&2
        exit 1
    fi
fi

# ================== HELPERS ==================
get_json() { kscreen-doctor -j; }

check_status() {
    local json="$1" output="$2" expected="$3"
    local status
    status=$(echo "$json" | jq -r --arg o "$output" '
        .outputs[] | select(.name == $o) | if .enabled then "enabled" else "disabled" end
    ')
    [[ "$status" == "$expected" ]] || { echo "Error: $output is $status (expected $expected)" >&2; exit 1; }
}

validate_outputs() {
    local json="$1"
    for out in "$KVM" "$PHYS1" "$PHYS2"; do
        echo "$json" | jq -e --arg o "$out" 'any(.outputs[]; .name == $o)' >/dev/null || {
            echo "Error: Output $out not found" >&2
            exit 1
        }
    done
}

# ================== MAIN ==================
MODE="${1:-toggle}"

# Detect current state for toggle
CURRENT_JSON=$(get_json)
validate_outputs "$CURRENT_JSON"

if [[ "$MODE" == "toggle" || -z "$MODE" ]]; then
    KVM_STATUS=$(echo "$CURRENT_JSON" | jq -r --arg o "$KVM" '
        .outputs[] | select(.name == $o) | if .enabled then "enabled" else "disabled" end
    ')

    if [[ "$KVM_STATUS" == "enabled" ]]; then
        echo "→ KVM detected, switching to physical displays..."
        TARGET="physical"
    else
        echo "→ Physical detected, switching to KVM..."
        TARGET="kvm"
    fi
else
    TARGET="$MODE"
fi

case "$TARGET" in
    kvm|KVM)
        echo "→ Switching to KVM display..."
        kscreen-doctor \
            "output.$KVM.enable" \
            "output.$KVM.primary" \
            "output.$PHYS1.disable" \
            "output.$PHYS2.disable"

        NEW_JSON=$(get_json)
        check_status "$NEW_JSON" "$KVM"   "enabled"
        check_status "$NEW_JSON" "$PHYS1" "disabled"
        check_status "$NEW_JSON" "$PHYS2" "disabled"
        echo "✓ KVM mode active"
        ;;

    physical|PHYSICAL)
        echo "→ Switching to physical displays..."
        kscreen-doctor \
            "output.$KVM.disable" \
            "output.$PHYS1.enable" \
            "output.$PHYS1.position.$PHYS1_POS" \
            "output.$PHYS1.primary" \
            "output.$PHYS2.enable" \
            "output.$PHYS2.position.$PHYS2_POS"

        NEW_JSON=$(get_json)
        check_status "$NEW_JSON" "$KVM"   "disabled"
        check_status "$NEW_JSON" "$PHYS1" "enabled"
        check_status "$NEW_JSON" "$PHYS2" "enabled"
        echo "✓ Physical dual-monitor mode active"
        ;;

    *)
        echo "Usage: $0 [kvm|physical|toggle]"
        echo "  (no argument = toggle)"
        exit 1
        ;;
esac
