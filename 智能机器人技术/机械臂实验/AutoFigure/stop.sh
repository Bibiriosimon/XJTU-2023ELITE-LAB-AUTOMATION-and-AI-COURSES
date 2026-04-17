#!/bin/bash
#
# AutoFigure - Stop Script
# Stops both backend and frontend servers
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Port configuration (must match start.sh)
BACKEND_PORT=8796
FRONTEND_PORT=6002

echo -e "${YELLOW}Stopping AutoFigure servers...${NC}"

# Function to get PIDs using a port (uses multiple methods for reliability)
get_port_pids() {
    local port=$1
    local pids=""

    # Try fuser first (most reliable)
    if command -v fuser &> /dev/null; then
        pids=$(fuser ${port}/tcp 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | tr '\n' ' ')
    fi

    # Fallback to lsof
    if [ -z "$pids" ] && command -v lsof &> /dev/null; then
        pids=$(lsof -t -i :$port 2>/dev/null | tr '\n' ' ')
    fi

    # Fallback to ss + ps
    if [ -z "$pids" ]; then
        pids=$(ss -tlnp 2>/dev/null | grep ":${port} " | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | tr '\n' ' ')
    fi

    echo "$pids"
}

# Function to kill all processes on a port
kill_port() {
    local port=$1
    local name=$2
    local pids=$(get_port_pids $port)
    if [ -n "$pids" ]; then
        echo -e "${YELLOW}Stopping $name on port $port (PIDs: $pids)${NC}"
        # First try graceful termination
        echo "$pids" | xargs -r kill 2>/dev/null || true
        sleep 1
        # Force kill if still running
        local remaining=$(get_port_pids $port)
        if [ -n "$remaining" ]; then
            echo -e "${YELLOW}Force killing remaining $name processes...${NC}"
            echo "$remaining" | xargs -r kill -9 2>/dev/null || true
            sleep 1
        fi
        # Verify stopped
        local check=$(get_port_pids $port)
        if [ -z "$check" ]; then
            echo -e "${GREEN}$name stopped successfully.${NC}"
        else
            echo -e "${RED}Warning: Some $name processes may still be running.${NC}"
        fi
    else
        echo -e "${GREEN}$name is not running.${NC}"
    fi
}

# Stop backend (by port - more reliable than PID file)
kill_port $BACKEND_PORT "Backend"

# Stop frontend (by port - catches npm and next-server child processes)
kill_port $FRONTEND_PORT "Frontend"

# Clean up PID files
rm -f /tmp/autofigure_backend.pid
rm -f /tmp/autofigure_frontend.pid

echo -e "${GREEN}AutoFigure servers stopped.${NC}"
