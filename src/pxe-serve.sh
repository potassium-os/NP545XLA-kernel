#!/bin/bash
# src/pxe-serve.sh — One-shot PXE server + netconsole listener
#
# Sets up the network interface, starts a UDP listener for kernel netconsole
# output, and runs tsbootkit-pxed with the config from src/tsbootkit.yaml.
# Cleans up on exit.
#
# Usage: sudo bash src/pxe-serve.sh [interface]
#
# Options:
#   --ip IP               Server IP (default: 192.168.202.5)
#   -n, --netconsole PORT  Netconsole UDP listen port (default: 6666)
#   --no-netconsole        Don't start the netconsole listener
#   -v, -vv, -vvv          Verbosity (passed to tsbootkit)
#
# The netconsole listener prints kernel log output to stdout AND saves it
# to pxe/netconsole.log. Useful for debugging early boot without a serial cable.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Defaults
IFACE="en6"
SERVER_IP="192.168.202.5"
NETCONSOLE_PORT=6666
SKIP_NETCONSOLE=false
VERBOSE=""
NETCONSOLE_LOG="$REPO_ROOT/pxe/netconsole.log"
CONFIG="$REPO_ROOT/src/tsbootkit.yaml"
RUNTIME_CONFIG=""

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--netconsole) NETCONSOLE_PORT="$2"; shift 2 ;;
        --ip)            SERVER_IP="$2"; shift 2 ;;
        --no-netconsole) SKIP_NETCONSOLE=true; shift ;;
        -vvv)            VERBOSE="$VERBOSE -vvv"; shift ;;
        -vv)             VERBOSE="$VERBOSE -vv"; shift ;;
        -v)              VERBOSE="$VERBOSE -v"; shift ;;
        -*)              echo "Unknown option: $1"; exit 1 ;;
        *)               IFACE="$1"; shift ;;
    esac
done

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

# Verify config
if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config not found at $CONFIG"
    exit 1
fi

# Generate a runtime config with the correct interface
# (don't modify the source file — it may be tracked by git)
RUNTIME_CONFIG=$(mktemp /tmp/tsbootkit-XXXXXX)
sed "s/^interface:.*/interface: $IFACE/" "$CONFIG" > "$RUNTIME_CONFIG"
# Also update tftpRoot to be absolute (tsbootkit resolves relative to cwd)
if [[ "$REPO_ROOT" != "/work" ]]; then
    sed -i '' "s|^tftpRoot:.*|tftpRoot: $REPO_ROOT/pxe/tftp|" "$RUNTIME_CONFIG"
fi

# Cleanup trap
NETCONSOLE_PID=""

cleanup() {
    echo ""
    echo "Cleaning up..."
    if [ -n "$NETCONSOLE_PID" ] && kill -0 "$NETCONSOLE_PID" 2>/dev/null; then
        kill "$NETCONSOLE_PID" 2>/dev/null || true
        wait "$NETCONSOLE_PID" 2>/dev/null || true
        echo "  ✓ netconsole listener stopped"
    fi
    # Belt and suspenders: kill anything still on the netconsole port
    if [ "$SKIP_NETCONSOLE" = false ] && command -v lsof &>/dev/null; then
        STALE=$(sudo lsof -ti UDP:"$NETCONSOLE_PORT" 2>/dev/null || true)
        if [ -n "$STALE" ]; then
            sudo kill $STALE 2>/dev/null || true
        fi
    fi
    # Clean up runtime config
    [ -f "$RUNTIME_CONFIG" ] && rm -f "$RUNTIME_CONFIG"
    echo "Done."
}
trap cleanup EXIT INT TERM

# Kill any stale listeners from previous runs
if [ "$SKIP_NETCONSOLE" = false ]; then
    # Kill stale socat/netcat on the netconsole port
    if command -v lsof &>/dev/null; then
        STALE=$(sudo lsof -ti UDP:"$NETCONSOLE_PORT" 2>/dev/null || true)
        if [ -n "$STALE" ]; then
            echo "Killing stale listener(s) on UDP $NETCONSOLE_PORT: $STALE"
            sudo kill $STALE 2>/dev/null || true
            sleep 0.5
        fi
    fi
fi

# Start netconsole listener
if [ "$SKIP_NETCONSOLE" = false ]; then
    if ! command -v socat &>/dev/null; then
        echo "ERROR: socat not found. Install with: brew install socat (macOS) or apt install socat (Linux)"
        exit 1
    fi

    mkdir -p "$(dirname "$NETCONSOLE_LOG")"
    echo "Starting netconsole listener on UDP $SERVER_IP:$NETCONSOLE_PORT..."
    echo "  (logging to $NETCONSOLE_LOG)"
    # Start socat in a background subshell that waits for the IP
    # so it doesn't block tsbootkit from starting
    (
        while true; do
            if command -v ip &>/dev/null; then
                HAS_IP=$(ip -4 addr show "$IFACE" 2>/dev/null | grep -c "inet $SERVER_IP" || true)
            else
                HAS_IP=$(ifconfig "$IFACE" 2>/dev/null | grep -c "inet $SERVER_IP" || true)
            fi
            [ "$HAS_IP" -gt 0 ] && break
            sleep 1
        done
        socat -u UDP-RECVFROM:$NETCONSOLE_PORT,bind=$SERVER_IP STDOUT &
        NETCONSOLE_PID=$!
        echo "  ✓ socat PID $NETCONSOLE_PID"
    ) &
fi

# Start tsbootkit-pxed with config
echo ""
echo "Starting tsbootkit-pxed (Ctrl+C to stop)..."
echo "  Interface:  $IFACE"
echo "  Config:     $RUNTIME_CONFIG (from $CONFIG)"
if [ "$SKIP_NETCONSOLE" = false ] && [ -n "$NETCONSOLE_PID" ]; then
    echo "  Netconsole: UDP $NETCONSOLE_PORT → $NETCONSOLE_LOG"
fi
echo ""

sudo tsbootkit-pxed --config "$RUNTIME_CONFIG" $VERBOSE
