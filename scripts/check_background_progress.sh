#!/bin/bash
# Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
#
# WSO2 LLC. licenses this file to you under the Apache License,
# Version 2.0 (the "License"); you may not use this file except
# in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# Monitor or stop a background load-test process.
# Can be called directly or via a thin proxy in a scenario scripts/ directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

show_usage() {
    echo "Usage: $0 [--dir <scripts-dir>] [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dir DIR            Directory where load_test_background.pid / .log files live"
    echo "  -l, --logs           Show available log files"
    echo "  -f, --follow         Follow the latest log file (tail -f)"
    echo "  -s, --stop           Stop the background process"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                   # Check background status"
    echo "  $0 --logs            # List all log files"
    echo "  $0 --follow          # Monitor live output"
    echo "  $0 --stop            # Stop background process"
    exit 0
}

# Parse --dir before other options
if [[ "$1" == "--dir" && -n "$2" ]]; then
    WORK_DIR="$2"
    shift 2
fi

PID_FILE="${WORK_DIR}/load_test_background.pid"

ACTION="status"
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--logs)   ACTION="logs";   shift ;;
        -f|--follow) ACTION="follow"; shift ;;
        -s|--stop)   ACTION="stop";   shift ;;
        -h|--help)   show_usage ;;
        *) echo "Unknown option: $1"; show_usage ;;
    esac
done

# ── List logs ─────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "logs" ]]; then
    echo -e "${BLUE}=== Available Log Files ===${NC}"
    LOG_FILES=$(ls -t "${WORK_DIR}"/load_test_background_*.log 2>/dev/null)
    if [[ -n "$LOG_FILES" ]]; then
        for log_file in $LOG_FILES; do
            echo -e "   ${CYAN}$(basename "$log_file")${NC} - $(date -r "$log_file" 2>/dev/null || stat -c %y "$log_file" 2>/dev/null || echo "unknown date")"
        done
        echo ""
        echo -e "${CYAN}To view a log: tail -20 'LOG_FILE_NAME'${NC}"
        echo -e "${CYAN}To follow live: tail -f 'LOG_FILE_NAME'${NC}"
    else
        echo -e "${YELLOW}No log files found.${NC}"
    fi
    exit 0
fi

# ── Follow latest log ─────────────────────────────────────────────────────────
if [[ "$ACTION" == "follow" ]]; then
    LATEST=$(ls -t "${WORK_DIR}"/load_test_background_*.log 2>/dev/null | head -1)
    if [[ -n "$LATEST" ]]; then
        echo -e "${BLUE}Following log file: ${CYAN}$(basename "$LATEST")${NC}"
        echo -e "${YELLOW}Press Ctrl+C to stop following${NC}"
        echo ""
        tail -f "$LATEST"
    else
        echo -e "${RED}No log files found to follow.${NC}"
        exit 1
    fi
    exit 0
fi

# ── Stop process ──────────────────────────────────────────────────────────────
if [[ "$ACTION" == "stop" ]]; then
    if [[ -f "$PID_FILE" ]]; then
        BACKGROUND_PID=$(cat "$PID_FILE")
        if ps -p "$BACKGROUND_PID" > /dev/null 2>&1; then
            echo -e "${YELLOW}Stopping background process (PID: $BACKGROUND_PID)...${NC}"
            kill "$BACKGROUND_PID"
            sleep 2
            if ps -p "$BACKGROUND_PID" > /dev/null 2>&1; then
                echo -e "${RED}Process still running, force killing...${NC}"
                kill -9 "$BACKGROUND_PID"
                sleep 1
            fi
            if ! ps -p "$BACKGROUND_PID" > /dev/null 2>&1; then
                echo -e "${GREEN}Background process stopped successfully${NC}"
                rm -f "$PID_FILE"
            else
                echo -e "${RED}Failed to stop process${NC}"
            fi
        else
            echo -e "${YELLOW}Process with PID $BACKGROUND_PID is not running${NC}"
            rm -f "$PID_FILE"
        fi
    else
        echo -e "${YELLOW}No background process found to stop${NC}"
    fi
    exit 0
fi

# ── Status ────────────────────────────────────────────────────────────────────
echo -e "${BLUE}=== Load Test Background Status ===${NC}"

if [[ ! -f "$PID_FILE" ]]; then
    echo -e "${YELLOW}No background load test found.${NC}"
    echo "PID file not found: $PID_FILE"
    echo ""

    LOG_FILES=$(ls -t "${WORK_DIR}"/load_test_background_*.log 2>/dev/null)
    if [[ -n "$LOG_FILES" ]]; then
        echo -e "${BLUE}Previous background test log files found:${NC}"
        for log_file in $LOG_FILES; do
            echo -e "   ${CYAN}$(basename "$log_file")${NC} - $(date -r "$log_file" 2>/dev/null || stat -c %y "$log_file" 2>/dev/null || echo "unknown date")"
        done
        echo ""
        echo -e "${CYAN}To view latest log: tail -20 '$(echo $LOG_FILES | cut -d' ' -f1)'${NC}"
    else
        echo -e "${BLUE}No previous background test logs found.${NC}"
    fi

    echo ""
    echo -e "${GREEN}To start a background load test:${NC}"
    echo -e "   ${CYAN}./load_test.sh --background${NC}"
    echo ""
    exit 0
fi

BACKGROUND_PID=$(cat "$PID_FILE")

if ps -p "$BACKGROUND_PID" > /dev/null 2>&1; then
    echo -e "${GREEN}Background load test is RUNNING${NC}"
    echo -e "   PID: ${CYAN}$BACKGROUND_PID${NC}"

    LATEST=$(ls -t "${WORK_DIR}"/load_test_background_*.log 2>/dev/null | head -1)
    if [[ -n "$LATEST" ]]; then
        echo -e "   Log: ${CYAN}$LATEST${NC}"
        echo ""
        echo -e "${BLUE}Recent log entries:${NC}"
        tail -10 "$LATEST"
        echo ""
        echo -e "${CYAN}To monitor live: tail -f '$LATEST'${NC}"
        echo -e "${CYAN}To stop process: $0 --stop${NC}"
    fi
else
    echo -e "${RED}Background load test is NOT running${NC}"
    echo -e "   PID $BACKGROUND_PID is not active"

    LATEST=$(ls -t "${WORK_DIR}"/load_test_background_*.log 2>/dev/null | head -1)
    if [[ -n "$LATEST" ]]; then
        echo -e "   Last log: ${CYAN}$LATEST${NC}"
        echo ""
        echo -e "${YELLOW}Last few log entries:${NC}"
        tail -20 "$LATEST"
    fi
    rm -f "$PID_FILE"
fi

echo ""
