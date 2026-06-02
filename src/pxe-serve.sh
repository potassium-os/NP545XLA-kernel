#!/bin/bash
# src/pxe-serve.sh — One-shot PXE server + netconsole listener
#
# Sets up the network interface, starts a UDP listener for kernel netconsole
# output, and runs tsbootkit-pxed. Cleans up on exit.
#
# Usage: sudo bash src/pxe-serve.sh [interface]
#
# Options:
#   -p, --http-port PORT   HTTP port (default: 8080)
#   -n, --netconsole PORT  Netconsole UDP listen port (default: 6666)
#   --no-netconsole        Don't start the netconsole listener
#   -v, -vv, -vvv          Verbosity (passed to tsbootkit)
#   --config FILE          Use tsbootkit YAML config instead of CLI flags
#
# The netconsole listener prints kernel log output to stdout AND saves it
# to pxe/netconsole.log. Useful for debugging early boot without a serial cable.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Defaults
IFACE=""
HTTP_PORT=8080
NETCONSOLE_PORT=6666
SKIP_NETCONSOLE=false
VERBOSE="-v"
CONFIG=""
SERVER_IP="192.168.202.5"
NETCONSOLE_LOG="$REPO_ROOT/pxe/netconsole.log"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--http-port)  HTTP_PORT="$2"; shift 2 ;;
        -n|--netconsole) NETCONSOLE_PORT="$2"; shift 2 ;;
        --no-netconsole) SKIP_NETCONSOLE=true; shift ;;
        -vvv)            VERBOSE="-vvv"; shift ;;
        -vv)             VERBOSE="-vv"; shift ;;
        -v)              VERBOSE="-v"; shift ;;
        --config)        CONFIG="$2"; shift 2 ;;
        -*)              echo "Unknown option: $1"; exit 1 ;;
        *)               IFACE="$1"; shift ;;
    esac
done

# Auto-detect USB ethernet interface if not specified
if [ -z "$IFACE" ]; then
    if command -v ip &>/dev/null; then
        IFACE=$(ip -br link 2>/dev/null | grep -i "enx\|eth" | awk '{print $1}' | head -1)
    fi
    if [ -z "$IFACE" ] && command -v networksetup &>/dev/null; then
        IFACE=$(networksetup -listallhardwareports 2>/dev/null | \
            grep -B1 -i "ethernet\|usb\|thunderbolt" | \
            grep "Device" | awk '{print $2}' | head -1)
    fi
fi

if [ -z "$IFACE" ]; then
    echo "ERROR: Could not detect USB ethernet interface."
    echo "Usage: sudo bash src/pxe-serve.sh [interface]"
    exit 1
fi

# Verify tsbootkit
if ! command -v tsbootkit-pxed &>/dev/null; then
    echo "ERROR: tsbootkit-pxed not found. Install with: npm install -g tsbootkit"
    exit 1
fi

# Cleanup trap
cleanup() {
    echo ""
    echo "Cleaning up..."
    if [ -n "$NETCONSOLE_PID" ] && kill -0 "$NETCONSOLE_PID" 2>/dev/null; then
        kill "$NETCONSOLE_PID" 2>/dev/null || true
        echo "  ✓ netconsole listener stopped"
    fi
    if [ -n "$TMUX_PID" ] && kill -0 "$TMUX_PID" 2>/dev/null; then
        kill "$TMUX_PID" 2>/dev/null || true
        echo "  ✓ tmux session stopped"
    fi
    # Remove IP assignment (best effort)
    if command -v ip &>/dev/null; then
        sudo ip addr del "$SERVER_IP/24" dev "$IFACE" 2>/dev/null || true
    else
        sudo ifconfig "$IFACE" 0.0.0.0 2>/dev/null || true
    fi
    echo "Done."
}
NETCONSOLE_PID=""
TMUX_PID=""
trap cleanup EXIT INT TERM

# Assign IP
echo "Setting $SERVER_IP on $IFACE..."
if command -v ip &>/dev/null; then
    sudo ip addr add "$SERVER_IP/24" dev "$IFACE" 2>/dev/null || true
    sudo ip link set "$IFACE" up
else
    sudo ifconfig "$IFACE" "$SERVER_IP" netmask 255.255.255.0 up
fi

# Start netconsole listener
if [ "$SKIP_NETCONSOLE" = false ]; then
    # Prefer socat (supports broadcast + multicast), fall back to netcat
    NETCONSOLE_CMD=""
    if command -v socat &>/dev/null; then
        NETCONSOLE_CMD="socat -u UDP-RECV:$NETCONSOLE_PORT,bind=$SERVER_IP,fork STDOUT"
    elif command -v nc &>/dev/null; then
        # Try GNU netcat with -u (UDP) -l (listen)
        if nc -u -l 2>&1 | grep -q "usage\|option"; then
            NETCONSOLE_CMD="nc -u -l $NETCONSOLE_PORT"
        fi
    fi

    if [ -n "$NETCONSOLE_CMD" ]; then
        mkdir -p "$(dirname "$NETCONSOLE_LOG")"
        echo "Starting netconsole listener on UDP $SERVER_IP:$NETCONSOLE_PORT..."
        echo "  (logging to $NETCONSOLE_LOG)"
        # Tee to both stdout and log file
        $NETCONSOLE_CMD | tee "$NETCONSOLE_LOG" &
        NETCONSOLE_PID=$!
        echo "  ✓ PID $NETCONSOLE_PID"
    else
        echo "WARNING: Neither socat nor netcat found. Skipping netconsole listener."
        echo "  Install socat: brew install socat (macOS) or apt install socat (Linux)"
    fi
fi

# Start tsbootkit-pxed
echo ""
echo "Starting tsbootkit-pxed (Ctrl+C to stop)..."
echo "  Interface:  $IFACE"
echo "  TFTP root:  $REPO_ROOT/pxe/tftp/"
echo "  HTTP port:  $HTTP_PORT"
if [ "$SKIP_NETCONSOLE" = false ] && [ -n "$NETCONSOLE_PID" ]; then
    echo "  Netconsole: UDP $NETCONSOLE_PORT → $NETCONSOLE_LOG"
fi
echo ""

if [ -n "$CONFIG" ]; then
    sudo tsbootkit-pxed "$IFACE" "$REPO_ROOT/pxe/tftp" BOOTAA64.EFI \
        --http-port "$HTTP_PORT" \
        --config "$CONFIG" \
        --wait \
        $VERBOSE
else
    sudo tsbootkit-pxed "$IFACE" "$REPO_ROOT/pxe/tftp" BOOTAA64.EFI \
        --http-port "$HTTP_PORT" \
        --wait \
        $VERBOSE
fi
