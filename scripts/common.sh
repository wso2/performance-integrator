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

# Shared utilities sourced by all load-test and capacity-planning scripts.

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Print helpers ─────────────────────────────────────────────────────────────
print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
}
print_info()     { echo -e "${CYAN}[INFO]${NC} $1"; }
print_success()  { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning()  { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()    { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_progress() { echo -e "${PURPLE}[PROGRESS]${NC} $1"; }

# ── Progress bar ──────────────────────────────────────────────────────────────
show_progress() {
    local duration=$1
    local interval=10
    local elapsed=0

    echo -ne "${YELLOW}Progress: ${NC}"
    while [ $elapsed -lt $duration ]; do
        local percentage=$((elapsed * 100 / duration))
        local filled=$((percentage / 5))
        local empty=$((20 - filled))
        printf "\r${YELLOW}Progress: ${NC}["
        printf "%*s" $filled | tr ' ' '='
        printf "%*s" $empty | tr ' ' '-'
        printf "] %d%% (%d/%ds)" $percentage $elapsed $duration
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    printf "\r${YELLOW}Progress: ${NC}[====================] 100%% (%ds/%ds)\n" $duration $duration
}

# ── JTL metrics parser ────────────────────────────────────────────────────────
# Usage:  parse_jtl_metrics <jtl_file>
# Output: throughput|error_pct|mean|stddev|min|max|p50|p90|p95|p99|recv_kb|sent_kb|total|failed
parse_jtl_metrics() {
    local jtl_file=$1
    tail -n +2 "$jtl_file" | awk -F',' '
        BEGIN { min_ts=9999999999999; max_ts=0; n=0; mean=0; M2=0; ok=0
                min_rt=999999999; max_rt=0; bytes_sum=0; sent_sum=0 }
        $1 ~ /^[0-9]+$/ {
            n++
            elapsed = $2
            delta = elapsed - mean; mean += delta / n; delta2 = elapsed - mean; M2 += delta * delta2
            ts = $1
            if (ts < min_ts) min_ts = ts
            if (ts > max_ts) max_ts = ts
            if ($8 == "true") ok++
            if (elapsed < min_rt) min_rt = elapsed
            if (elapsed > max_rt) max_rt = elapsed
            times[n] = elapsed
            bytes_sum += $10 + 0
            sent_sum  += $11 + 0
        }
        END {
            if (n == 0) { print "0|0|0|0|0|0|0|0|0|0|0|0|0|0"; exit }
            stddev = (n > 1) ? sqrt(M2 / (n - 1)) : 0
            asort(times)
            n50 = int(n * 0.50); if (n50 < 1) n50 = 1
            n90 = int(n * 0.90); if (n90 < 1) n90 = 1
            n95 = int(n * 0.95); if (n95 < 1) n95 = 1
            n99 = int(n * 0.99); if (n99 < 1) n99 = 1
            duration_s = (max_ts > min_ts) ? (max_ts - min_ts) / 1000.0 : 1
            tput      = (max_ts > min_ts) ? (n * 1000.0) / (max_ts - min_ts) : 0
            recv_kb   = bytes_sum / 1024.0 / duration_s
            sent_kb   = sent_sum  / 1024.0 / duration_s
            failed    = n - ok
            err_pct   = (failed * 100.0) / n
            printf "%.2f|%.2f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.0f|%.2f|%.2f|%d|%d",
                tput, err_pct, mean, stddev, min_rt, max_rt,
                times[n50], times[n90], times[n95], times[n99],
                recv_kb, sent_kb, n, failed
        }'
}

# ── Validate positive integers ────────────────────────────────────────────────
# Usage: validate_positive_integers <label> <values...>
validate_positive_integers() {
    local label=$1
    shift
    local invalid=()
    for val in "$@"; do
        if ! [[ "$val" =~ ^[0-9]+$ ]] || [[ "$val" -le 0 ]]; then
            invalid+=("$val")
        fi
    done
    if [[ ${#invalid[@]} -gt 0 ]]; then
        print_error "Invalid ${label}: ${invalid[*]}"
        print_info "${label} must be positive integers"
        exit 1
    fi
}

# ── JMeter common save-service flags ─────────────────────────────────────────
JMETER_SAVE_FLAGS=(
    -Dsummariser.name=summary
    -Dsummariser.interval=30
    -Dsummariser.out=true
    -Djmeter.save.saveservice.output_format=csv
    -Djmeter.save.saveservice.response_data=false
    -Djmeter.save.saveservice.samplerData=false
    -Djmeter.save.saveservice.requestHeaders=false
    -Djmeter.save.saveservice.responseHeaders=false
    -Djmeter.save.saveservice.print_field_names=true
)

# ── JMeter runner (stdbuf-aware, preserves JMeter exit code) ─────────────────
# Usage: run_with_tee <log_file> <command> [args...]
# Returns the exit code of <command>, not tee.
run_with_tee() {
    local log_file=$1
    shift
    local exit_code
    if command -v stdbuf &> /dev/null; then
        stdbuf -oL -eL "$@" 2>&1 | stdbuf -oL -eL tee "$log_file"
    else
        "$@" 2>&1 | tee "$log_file"
    fi
    exit_code=${PIPESTATUS[0]}
    return $exit_code
}

# ── Background mode handler ───────────────────────────────────────────────────
# Call with the original script arguments: handle_background_mode "$@"
# Requires globals: BACKGROUND_MODE, DRY_RUN, SCRIPT_DIR, TIMESTAMP
handle_background_mode() {
    if [ "$BACKGROUND_MODE" = true ] && [ "$DRY_RUN" = false ]; then
        local BACKGROUND_LOG="${SCRIPT_DIR}/load_test_background_${TIMESTAMP}.log"

        if [ -z "$LOAD_TEST_BACKGROUND" ]; then
            print_info "Starting load test in background mode..."
            print_info "Output will be logged to: $BACKGROUND_LOG"
            print_info "Monitor progress with: tail -f $BACKGROUND_LOG"
            print_info "Process will continue even if SSH connection is lost."
            echo ""

            export LOAD_TEST_BACKGROUND=1
            nohup "$SCRIPT_DIR/$(basename "$0")" "$@" > "$BACKGROUND_LOG" 2>&1 &
            local BACKGROUND_PID=$!

            print_success "Background process started with PID: $BACKGROUND_PID"
            print_info "Log file: $BACKGROUND_LOG"
            print_info "To monitor: tail -f '$BACKGROUND_LOG'"
            print_info "To stop: kill $BACKGROUND_PID"
            echo $BACKGROUND_PID > "${SCRIPT_DIR}/load_test_background.pid"
            print_info "PID saved to: ${SCRIPT_DIR}/load_test_background.pid"
            exit 0
        fi

        print_info "Running in background mode (PID: $$)"
        print_info "Output is being logged to: $BACKGROUND_LOG"
    fi
}
