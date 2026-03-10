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

# Interactive multi-scenario capacity planning test with per-scenario warmup.
# Generates a cartesian scenario matrix from -r/-t/-p flags (outer: payloads, inner: RPS x threads).
# Pauses between scenarios to allow manual service restarts for clean JVM state.
#
# Required env vars: DOMAIN, AUTH_HEADER
# Example:
#   export DOMAIN="your.domain.com"
#   export AUTH_HEADER="Bearer your_token"
#
#   # Foreground (interactive):
#   ./interactive_test.sh -r 100,500 -t 10,50 -p 1KB,10KB
#
#   # Background (SSH-safe):
#   ./interactive_test.sh -r 100,500 -t 10,50 -p 1KB,10KB --background
#   ./interactive_test.sh --resume   # run after restarting the service

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../scripts/common.sh"

PAYLOADS_DIR="$SCRIPT_DIR/../../../payloads/passthrough"
JMETER_PATH="$SCRIPT_DIR/../apache-jmeter-5.6.3/bin/jmeter"
TEST_PLAN="$SCRIPT_DIR/test.jmx"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="$SCRIPT_DIR/logs/${TIMESTAMP}"
RESULTS_DIR="$SCRIPT_DIR/results/${TIMESTAMP}"

STATE_FILE="${SCRIPT_DIR}/.interactive_state"

# ── Defaults ──────────────────────────────────────────────────────────────────
DEFAULT_DURATION=600
DEFAULT_WARMUP_DURATION=120
WARMUP_COOLDOWN=30
DEFAULT_RPS_TARGETS=(10 50 100 200 500 1000 2000 5000)
DEFAULT_THREAD_COUNTS=(10 50 100 500)
DEFAULT_PAYLOADS=("1KB" "10KB" "50KB" "100KB" "250KB" "1MB")

DURATION=$DEFAULT_DURATION
WARMUP_DURATION=$DEFAULT_WARMUP_DURATION
RPS_TARGETS=("${DEFAULT_RPS_TARGETS[@]}")
THREAD_COUNTS=("${DEFAULT_THREAD_COUNTS[@]}")
PAYLOADS=("${DEFAULT_PAYLOADS[@]}")
BACKGROUND_MODE=false
RESUME_MODE=false
DRY_RUN=false

RESUME_PIPE=""

# ── Usage ─────────────────────────────────────────────────────────────────────
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "       $0 --resume"
    echo ""
    echo "Options:"
    echo "  -r, --rps RPS_LIST            Comma-separated list of target RPS (e.g., 100,500,1000)"
    echo "  -t, --threads THREAD_LIST     Comma-separated list of concurrent connections (e.g., 10,50,100)"
    echo "  -p, --payloads PAYLOAD_LIST   Comma-separated list of payloads (e.g., 1KB,10KB)"
    echo "  -d, --duration SECONDS        Test duration per scenario in seconds (default: $DEFAULT_DURATION)"
    echo "  --warmup-duration SECONDS     Warmup duration in seconds (default: $DEFAULT_WARMUP_DURATION)"
    echo "  -b, --background              Run in background mode (survives SSH disconnection)"
    echo "  --resume                      Resume a paused background run after service restart"
    echo "  -n, --dry-run                 Show scenario matrix without running tests"
    echo "  -h, --help                    Show this help message"
    echo ""
    echo "Available payloads: 1KB, 10KB, 50KB, 100KB, 250KB, 1MB"
    echo "Default RPS targets: ${DEFAULT_RPS_TARGETS[*]}"
    echo "Default thread counts: ${DEFAULT_THREAD_COUNTS[*]}"
    echo ""
    echo "Warmup per scenario: same payload and threads, 10% of target RPS (minimum 1)"
    exit "${1:-1}"
}

# ── Argument parsing ──────────────────────────────────────────────────────────
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--rps)
                [[ -z "$2" ]] && { print_error "--rps requires a value"; show_usage; }
                IFS=',' read -ra RPS_TARGETS <<< "$2"; shift 2 ;;
            -t|--threads)
                [[ -z "$2" ]] && { print_error "--threads requires a value"; show_usage; }
                IFS=',' read -ra THREAD_COUNTS <<< "$2"; shift 2 ;;
            -p|--payloads)
                [[ -z "$2" ]] && { print_error "--payloads requires a value"; show_usage; }
                IFS=',' read -ra PAYLOADS <<< "$2"; shift 2 ;;
            -d|--duration)
                [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]] && { print_error "--duration requires a positive integer"; show_usage; }
                DURATION=$2; shift 2 ;;
            --warmup-duration)
                [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]] && { print_error "--warmup-duration requires a positive integer"; show_usage; }
                WARMUP_DURATION=$2; shift 2 ;;
            -b|--background) BACKGROUND_MODE=true; shift ;;
            --resume)        RESUME_MODE=true; shift ;;
            -n|--dry-run)    DRY_RUN=true; shift ;;
            -h|--help)       show_usage 0 ;;
            *) print_error "Unknown option: $1"; show_usage ;;
        esac
    done
}

# ── Warmup RPS: 10% of target RPS, minimum 1 ─────────────────────────────────
compute_warmup_rps() {
    local rps=$1
    local warmup=$(( rps / 10 ))
    [[ $warmup -lt 1 ]] && warmup=1
    echo $warmup
}

# ── Payload validation ────────────────────────────────────────────────────────
validate_payloads() {
    local invalid=()
    for payload in "${PAYLOADS[@]}"; do
        [[ ! -f "$PAYLOADS_DIR/${payload}.txt" ]] && invalid+=("$payload")
    done
    if [[ ${#invalid[@]} -gt 0 ]]; then
        print_error "Invalid payload files: ${invalid[*]}"
        print_info "Available payloads in $PAYLOADS_DIR:"
        ls -1 "$PAYLOADS_DIR"/*.txt 2>/dev/null | sed "s|$PAYLOADS_DIR/||;s/.txt$//" | sed 's/^/  /'
        exit 1
    fi
}

# ── JTL filename helper ───────────────────────────────────────────────────────
create_jtl_filename() {
    local rps=$1 threads=$2 payload=$3 test_type=$4
    echo "${RESULTS_DIR}/${test_type}_${rps}rps_${threads}threads_${payload%.*}_${TIMESTAMP}.jtl"
}

# ── Summary report ────────────────────────────────────────────────────────────
generate_summary_report() {
    local jtl_file=$1 rps=$2 threads=$3 payload=$4 test_type=$5 summary_file=${6:-""}

    [[ ! -f "$jtl_file" ]] && { print_warning "JTL file not found: $jtl_file"; return 1; }

    print_info "Extracting metrics from JTL file..."
    local stats
    stats=$(parse_jtl_metrics "$jtl_file")

    [[ -z "$stats" || "$stats" == "0|0|0|0|0|0|0|0|0|0|0|0|0|0" ]] && {
        print_warning "Could not extract metrics from: $jtl_file"; return 1; }

    local throughput error_pct mean_res stddev_res min_res max_res p50 p90 p95 p99 recv_kb sent_kb total_samples failed_samples
    IFS='|' read -r throughput error_pct mean_res stddev_res min_res max_res p50 p90 p95 p99 recv_kb sent_kb total_samples failed_samples <<< "$stats"
    local successful_samples=$((total_samples - failed_samples))
    local throughput_achievement
    throughput_achievement=$(awk "BEGIN {printf \"%.1f\", ($throughput/$rps)*100}")

    local report_file="${RESULTS_DIR}/${test_type}_${rps}rps_${threads}threads_${payload}_summary_${TIMESTAMP}.txt"
    cat > "$report_file" << EOF
Load Test Summary Report
========================
Test Configuration:
- Test Type: $test_type
- Target RPS: $rps
- Concurrent Connections: $threads
- Payload: $payload
- Generated: $(date)
- JTL File: $(basename "$jtl_file")

Performance Metrics:
- Total Samples: $total_samples
- Successful Samples: $successful_samples
- Failed Samples: $failed_samples
- Error Rate: $error_pct %
- Actual Throughput: $throughput req/sec
- Throughput Achievement: ${throughput_achievement}%

Response Times:
- Mean Response Time: $mean_res ms
- Std Dev Response Time: $stddev_res ms
- Min Response Time: $min_res ms
- Max Response Time: $max_res ms
- 50th Percentile (Median): $p50 ms
- 90th Percentile: $p90 ms
- 95th Percentile: $p95 ms
- 99th Percentile: $p99 ms

Network Throughput:
- Received: $recv_kb KB/sec
- Sent: $sent_kb KB/sec
EOF

    if [[ -n "$summary_file" ]]; then
        {
            echo "Performance Metrics for ${rps} RPS, ${threads} threads, ${payload} payload (${test_type}):"
            echo "  - Total Samples: ${total_samples} (${successful_samples} ok, ${failed_samples} failed)"
            echo "  - Error Rate: ${error_pct}%"
            echo "  - Actual Throughput: ${throughput} req/sec (${throughput_achievement}% of target)"
            echo "  - Mean Response Time: ${mean_res} ms"
            echo "  - Min/Max Response Time: ${min_res} ms / ${max_res} ms"
            echo "  - 90th Percentile: ${p90} ms"
            echo "  - 95th Percentile: ${p95} ms"
            echo "  - 99th Percentile: ${p99} ms"
            echo "  - Network: ${recv_kb} KB/sec received, ${sent_kb} KB/sec sent"
            echo ""
        } >> "$summary_file"
    fi

    echo ""
    print_success "Test Summary:"
    echo -e "  ${CYAN}Total Samples:${NC} ${GREEN}$total_samples${NC}"
    echo -e "  ${CYAN}Error Rate:${NC} ${RED}$error_pct${NC} %"
    echo -e "  ${CYAN}Target RPS:${NC} ${PURPLE}$rps${NC} req/sec"
    echo -e "  ${CYAN}Actual Throughput:${NC} ${GREEN}$throughput${NC} req/sec (${throughput_achievement}%)"
    echo -e "  ${CYAN}Concurrent Connections:${NC} ${BLUE}$threads${NC}"
    echo -e "  ${CYAN}Mean Response Time:${NC} ${YELLOW}$mean_res${NC} ms"
    echo -e "  ${CYAN}Min/Max Response Time:${NC} ${GREEN}$min_res${NC} / ${RED}$max_res${NC} ms"
    echo -e "  ${CYAN}90th Percentile:${NC} ${YELLOW}$p90${NC} ms"
    echo -e "  ${CYAN}95th Percentile:${NC} ${YELLOW}$p95${NC} ms"
    echo -e "  ${CYAN}99th Percentile:${NC} ${YELLOW}$p99${NC} ms"
    echo -e "  ${CYAN}Network:${NC} ${BLUE}$recv_kb${NC} KB/sec recv, ${BLUE}$sent_kb${NC} KB/sec sent"
    echo -e "  ${CYAN}Summary Report:${NC} $report_file"
    echo ""
}

# ── Run a single JMeter test ──────────────────────────────────────────────────
run_jmeter_test() {
    local rps=$1 threads=$2 duration=$3 payload=$4 test_type=$5 description=$6 summary_file=${7:-""}
    local payload_file="${payload}.txt"
    local jtl_file
    jtl_file=$(create_jtl_filename "$rps" "$threads" "$payload_file" "$test_type")
    local log_file="${LOG_DIR}/${test_type}_${rps}rps_${threads}threads_${payload}_${TIMESTAMP}.log"

    print_progress "$description"
    echo -e "  ${CYAN}Target RPS:${NC} $rps | ${CYAN}Threads:${NC} $threads | ${CYAN}Duration:${NC} $duration seconds | ${CYAN}Payload:${NC} $payload"
    print_info "Live JMeter output:"
    echo -e "${YELLOW}===========================================${NC}"

    run_with_tee "$log_file" "$JMETER_PATH" -n -t "$TEST_PLAN" \
        -JtargetRPS="$rps" \
        -Jthreads="$threads" \
        -Jduration="$duration" \
        -Jpayload="$PAYLOADS_DIR/$payload_file" \
        -Jdomain="${DOMAIN}" \
        -JauthHeader="${AUTH_HEADER}" \
        -l "$jtl_file" \
        "${JMETER_SAVE_FLAGS[@]}"
    local exit_code=$?

    echo -e "${YELLOW}===========================================${NC}"

    if [ $exit_code -eq 0 ]; then
        print_success "Test completed successfully"
        generate_summary_report "$jtl_file" "$rps" "$threads" "$payload" "$test_type" "$summary_file"
    else
        print_error "Test failed with exit code: $exit_code"
    fi

    echo ""
    return $exit_code
}

# ── State file helpers ────────────────────────────────────────────────────────
write_state() {
    local current=$1
    {
        echo "FIFO_PATH=${RESUME_PIPE}"
        echo "PID=$$"
        echo "CURRENT=$current"
        echo "TOTAL=${TOTAL_SCENARIOS}"
        echo "TIMESTAMP=${TIMESTAMP}"
        echo "RESULTS_DIR=${RESULTS_DIR}"
    } > "$STATE_FILE"
}

read_state_field() {
    local field=$1
    grep "^${field}=" "$STATE_FILE" | cut -d'=' -f2-
}

# ── Cleanup on exit ───────────────────────────────────────────────────────────
cleanup() {
    [[ -p "$RESUME_PIPE" ]] && rm -f "$RESUME_PIPE"
    rm -f "$STATE_FILE"
}

# ── Resume: send signal to a waiting background process ──────────────────────
handle_resume() {
    if [[ ! -f "$STATE_FILE" ]]; then
        print_error "No active interactive test state found."
        print_info "Is a background interactive test currently running and waiting?"
        exit 1
    fi

    local fifo_path pid current total
    fifo_path=$(read_state_field "FIFO_PATH")
    pid=$(read_state_field "PID")
    current=$(read_state_field "CURRENT")
    total=$(read_state_field "TOTAL")

    if ! ps -p "$pid" > /dev/null 2>&1; then
        print_error "Background process (PID: $pid) is no longer running."
        rm -f "$STATE_FILE"
        exit 1
    fi

    if [[ ! -p "$fifo_path" ]]; then
        print_error "Resume pipe not found: $fifo_path"
        print_info "The background process may not be at a pause point yet."
        print_info "Check the log: tail -f \$(ls -t ${SCRIPT_DIR}/interactive_test_background_*.log | head -1)"
        exit 1
    fi

    print_info "Resuming background interactive test (scenario $current of $total)..."
    print_info "Sending resume signal (will block briefly until the process is ready)..."
    echo "resume" > "$fifo_path"
    print_success "Signal sent. Background test is now starting the next scenario."
    print_info "Monitor with: tail -f \$(ls -t ${SCRIPT_DIR}/interactive_test_background_*.log | head -1)"
    exit 0
}

# ── Pause between scenarios ───────────────────────────────────────────────────
pause_for_restart() {
    local current=$1 total=$2

    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}  SCENARIO ${current} of ${total} COMPLETE${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo -e "${YELLOW}  Restart the service instance now to ensure a${NC}"
    echo -e "${YELLOW}  clean JVM state for the next scenario.${NC}"

    if [ "$BACKGROUND_MODE" = true ]; then
        write_state "$current"
        echo -e "${CYAN}  When ready, run:${NC} ./interactive_test.sh --resume"
        echo -e "${BLUE}================================================${NC}"
        echo ""
        read -r < "$RESUME_PIPE"
        print_info "Resumed. Starting next scenario..."
    else
        echo -e "${CYAN}  When ready, press Enter to continue...${NC}"
        echo -e "${BLUE}================================================${NC}"
        echo ""
        read -r
        print_info "Continuing..."
    fi
    echo ""
}

# ── Background mode handler ───────────────────────────────────────────────────
handle_background_mode() {
    if [ "$BACKGROUND_MODE" = true ] && [ "$DRY_RUN" = false ]; then
        local BACKGROUND_LOG="${SCRIPT_DIR}/interactive_test_background_${TIMESTAMP}.log"

        if [ -z "$INTERACTIVE_TEST_BACKGROUND" ]; then
            print_info "Starting interactive test in background mode..."
            print_info "Output will be logged to: $BACKGROUND_LOG"
            print_info "Monitor progress with: tail -f $BACKGROUND_LOG"
            print_info "Process will continue even if SSH connection is lost."
            echo ""

            export INTERACTIVE_TEST_BACKGROUND=1
            nohup "$SCRIPT_DIR/$(basename "$0")" "$@" > "$BACKGROUND_LOG" 2>&1 &
            local BACKGROUND_PID=$!

            print_success "Background process started with PID: $BACKGROUND_PID"
            print_info "Log file: $BACKGROUND_LOG"
            print_info "To monitor:    tail -f '$BACKGROUND_LOG'"
            print_info "To resume:     ./interactive_test.sh --resume"
            print_info "To stop:       kill $BACKGROUND_PID"
            exit 0
        fi

        print_info "Running in background mode (PID: $$)"
        print_info "Output is being logged."
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
parse_arguments "$@"

# --resume is handled immediately before anything else
if [ "$RESUME_MODE" = true ]; then
    handle_resume
fi

handle_background_mode "$@"

if [ "$DRY_RUN" = true ]; then
    print_header "DRY RUN MODE - SCENARIO MATRIX PREVIEW"
else
    print_header "INTERACTIVE TEST INITIALIZATION"
fi

print_info "Validating arguments..."
validate_payloads
validate_positive_integers "RPS targets" "${RPS_TARGETS[@]}"
validate_positive_integers "thread counts" "${THREAD_COUNTS[@]}"

TOTAL_SCENARIOS=$(( ${#PAYLOADS[@]} * ${#RPS_TARGETS[@]} * ${#THREAD_COUNTS[@]} ))

print_info "Scenario Matrix (${TOTAL_SCENARIOS} scenarios — outer: payloads, inner: RPS x threads):"
scenario_idx=0
for P in "${PAYLOADS[@]}"; do
    for R in "${RPS_TARGETS[@]}"; do
        for T in "${THREAD_COUNTS[@]}"; do
            scenario_idx=$((scenario_idx + 1))
            WR=$(compute_warmup_rps "$R")
            echo -e "  ${PURPLE}[$scenario_idx/$TOTAL_SCENARIOS]${NC} ${CYAN}$R RPS${NC} x ${CYAN}$T threads${NC} x ${CYAN}$P${NC} | warmup: $WR RPS, ${WARMUP_DURATION}s | test: $R RPS, ${DURATION}s"
        done
    done
done
echo ""

if [ "$DRY_RUN" = true ]; then
    print_header "DRY RUN COMPLETED"
    print_success "Total scenarios that would be executed: $TOTAL_SCENARIOS"
    exit 0
fi

print_info "Checking environment variables..."
[[ -z "$DOMAIN" ]]      && { print_error "DOMAIN is not set. Example: export DOMAIN=\"your.domain.com\""; exit 1; }
[[ -z "$AUTH_HEADER" ]] && { print_error "AUTH_HEADER is not set. Example: export AUTH_HEADER=\"Bearer token\""; exit 1; }

print_info "Checking JMeter installation..."
[[ ! -f "$JMETER_PATH" ]] && { print_error "JMeter not found at: $JMETER_PATH"; exit 1; }
[[ ! -f "$TEST_PLAN" ]]   && { print_error "Test plan not found: $TEST_PLAN"; exit 1; }

if ! mkdir -p "$LOG_DIR" "$RESULTS_DIR"; then
    print_error "Failed to create directories $LOG_DIR and $RESULTS_DIR"
    exit 1
fi

print_success "Validation completed"
echo ""

SUMMARY_FILE="${RESULTS_DIR}/test_summary_${TIMESTAMP}.txt"
{
    echo "Interactive Load Test Summary - $(date)"
    echo "Domain: $DOMAIN"
    echo "Duration: $DURATION seconds per scenario | Warmup: $WARMUP_DURATION seconds"
    echo "RPS Targets: ${RPS_TARGETS[*]} | Threads: ${THREAD_COUNTS[*]} | Payloads: ${PAYLOADS[*]}"
    echo "Total scenarios: $TOTAL_SCENARIOS"
    echo "==========================================="
    echo ""
} > "$SUMMARY_FILE"

# ── Set up FIFO and state file for background mode ────────────────────────────
if [ "$BACKGROUND_MODE" = true ]; then
    RESUME_PIPE="${SCRIPT_DIR}/.resume_pipe_${TIMESTAMP}"
    mkfifo "$RESUME_PIPE"
    write_state 0
    trap cleanup EXIT INT TERM
fi

# ── Scenario loop ─────────────────────────────────────────────────────────────
CURRENT_SCENARIO=0

for PAYLOAD in "${PAYLOADS[@]}"; do
    for RPS in "${RPS_TARGETS[@]}"; do
        for THREADS in "${THREAD_COUNTS[@]}"; do
            CURRENT_SCENARIO=$((CURRENT_SCENARIO + 1))
            WARMUP_RPS=$(compute_warmup_rps "$RPS")

            print_header "SCENARIO $CURRENT_SCENARIO OF $TOTAL_SCENARIOS: ${RPS} RPS x ${THREADS} threads x ${PAYLOAD}"

            # ── Warmup ────────────────────────────────────────────────────────
            print_header "  WARMUP"
            if run_jmeter_test "$WARMUP_RPS" "$THREADS" "$WARMUP_DURATION" "$PAYLOAD" "warmup" \
                    "Warmup: ${WARMUP_RPS} RPS, ${THREADS} threads for ${WARMUP_DURATION}s with ${PAYLOAD} payload" "$SUMMARY_FILE"; then
                echo "Scenario $CURRENT_SCENARIO Warmup - SUCCESS" >> "$SUMMARY_FILE"
            else
                echo "Scenario $CURRENT_SCENARIO Warmup - FAILED" >> "$SUMMARY_FILE"
                print_warning "Warmup failed, continuing with main test..."
            fi

            print_info "Warmup cooldown (${WARMUP_COOLDOWN} seconds)..."
            show_progress $WARMUP_COOLDOWN

            # ── Main test ─────────────────────────────────────────────────────
            print_header "  LOAD TEST"
            if run_jmeter_test "$RPS" "$THREADS" "$DURATION" "$PAYLOAD" "loadtest" \
                    "Load test: ${RPS} RPS, ${THREADS} threads, ${PAYLOAD} payload, ${DURATION}s" "$SUMMARY_FILE"; then
                echo "Scenario $CURRENT_SCENARIO LoadTest ${RPS} RPS ${THREADS} threads ${PAYLOAD} - SUCCESS" >> "$SUMMARY_FILE"
            else
                echo "Scenario $CURRENT_SCENARIO LoadTest ${RPS} RPS ${THREADS} threads ${PAYLOAD} - FAILED" >> "$SUMMARY_FILE"
            fi

            # ── Pause for service restart (skip after last scenario) ──────────
            if [ $CURRENT_SCENARIO -lt $TOTAL_SCENARIOS ]; then
                pause_for_restart "$CURRENT_SCENARIO" "$TOTAL_SCENARIOS"
            fi
        done
    done
done

# ── Completion ────────────────────────────────────────────────────────────────
{
    echo ""
    echo "Test completed at: $(date)"
    echo "Total scenarios run: $TOTAL_SCENARIOS"
    echo ""
    echo "Reports: $RESULTS_DIR/*_summary_*.txt"
    echo "Logs:    $LOG_DIR/*.log"
} >> "$SUMMARY_FILE"

print_header "ALL SCENARIOS COMPLETED"
print_success "All interactive scenarios completed!"
print_info "Summary: $SUMMARY_FILE"
print_info "Results: $RESULTS_DIR"
