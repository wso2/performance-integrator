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

# Interactive multi-scenario performance test with per-scenario warmup.
# Generates a cartesian scenario matrix from -u/-p flags (outer: payloads, inner: users).
# Pauses between scenarios to allow manual service restarts for clean JVM state.
#
# Required env vars: DOMAIN, AUTH_HEADER
# Example:
#   export DOMAIN="your.domain.com"
#   export AUTH_HEADER="Bearer your_token"
#
#   # Foreground (interactive):
#   ./interactive_test.sh -u 100,500 -p 1KB,10KB
#
#   # Background (SSH-safe):
#   ./interactive_test.sh -u 100,500 -p 1KB,10KB --background
#   ./interactive_test.sh --resume   # run after restarting the service

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../scripts/common.sh"

PAYLOADS_DIR="$SCRIPT_DIR/../../../payloads/transformation"
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
DEFAULT_USER_COUNTS=(100 200 500 1000)
DEFAULT_PAYLOADS=("1KB" "10KB" "50KB" "100KB")

DURATION=$DEFAULT_DURATION
WARMUP_DURATION=$DEFAULT_WARMUP_DURATION
USER_COUNTS=("${DEFAULT_USER_COUNTS[@]}")
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
    echo "  -u, --users USER_LIST        Comma-separated list of user counts (e.g., 100,200,500)"
    echo "  -p, --payloads PAYLOAD_LIST  Comma-separated list of payloads (e.g., 1KB,10KB)"
    echo "  -d, --duration SECONDS       Test duration per scenario in seconds (default: $DEFAULT_DURATION)"
    echo "  --warmup-duration SECONDS    Warmup duration in seconds (default: $DEFAULT_WARMUP_DURATION)"
    echo "  -b, --background             Run in background mode (survives SSH disconnection)"
    echo "  --resume                     Resume a paused background run after service restart"
    echo "  -n, --dry-run                Show scenario matrix without running tests"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Available payloads: 1KB, 10KB, 50KB, 100KB"
    echo "Default users: ${DEFAULT_USER_COUNTS[*]}"
    echo ""
    echo "Warmup per scenario: same payload, 10% of test users (minimum 10)"
    exit "${1:-1}"
}

# ── Argument parsing ──────────────────────────────────────────────────────────
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--users)
                [[ -z "$2" ]] && { print_error "--users requires a value"; show_usage; }
                IFS=',' read -ra USER_COUNTS <<< "$2"; shift 2 ;;
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

# ── Warmup user count: 10% of test users, minimum 10 ─────────────────────────
compute_warmup_users() {
    local users=$1
    local warmup=$(( users / 10 ))
    [[ $warmup -lt 10 ]] && warmup=10
    echo $warmup
}

# ── Payload validation ────────────────────────────────────────────────────────
validate_payloads() {
    local invalid=()
    for payload in "${PAYLOADS[@]}"; do
        [[ ! -f "$PAYLOADS_DIR/${payload}.json" ]] && invalid+=("$payload")
    done
    if [[ ${#invalid[@]} -gt 0 ]]; then
        print_error "Invalid payload files: ${invalid[*]}"
        print_info "Available payloads in $PAYLOADS_DIR:"
        ls -1 "$PAYLOADS_DIR"/*.json 2>/dev/null | sed "s|$PAYLOADS_DIR/||;s/.json$//" | sed 's/^/  /'
        exit 1
    fi
}

# ── JTL filename helper ───────────────────────────────────────────────────────
create_jtl_filename() {
    local users=$1 payload=$2 test_type=$3
    echo "${RESULTS_DIR}/${test_type}_${users}users_${payload%.*}_${TIMESTAMP}.jtl"
}

# ── Summary report ────────────────────────────────────────────────────────────
generate_summary_report() {
    local jtl_file=$1 users=$2 payload=$3 test_type=$4 summary_file=${5:-""}

    [[ ! -f "$jtl_file" ]] && { print_warning "JTL file not found: $jtl_file"; return 1; }

    print_info "Extracting metrics from JTL file..."
    local stats
    stats=$(parse_jtl_metrics "$jtl_file")

    [[ -z "$stats" || "$stats" == "0|0|0|0|0|0|0|0|0|0|0|0|0|0" ]] && {
        print_warning "Could not extract metrics from: $jtl_file"; return 1; }

    local throughput error_rate avg_response_time std_dev min_res max_res p50 p90 p95 p99 recv_kb sent_kb total_samples failed_samples
    IFS='|' read -r throughput error_rate avg_response_time std_dev min_res max_res p50 p90 p95 p99 recv_kb sent_kb total_samples failed_samples <<< "$stats"
    local successful_samples=$((total_samples - failed_samples))

    local report_file="${RESULTS_DIR}/${test_type}_${users}users_${payload}_summary_${TIMESTAMP}.txt"
    cat > "$report_file" << EOF
Load Test Summary Report
========================
Test Configuration:
- Test Type: $test_type
- Users: $users
- Payload: $payload
- Generated: $(date)
- JTL File: $(basename "$jtl_file")

Performance Metrics:
- Total Samples: $total_samples
- Successful Samples: $successful_samples
- Failed Samples: $failed_samples
- Throughput: $throughput req/sec
- Error Rate: $error_rate %

Response Times:
- Avg Response Time: $avg_response_time ms
- Std Dev Response Time: $std_dev ms
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
            echo "Performance Metrics for ${users} users with ${payload} payload (${test_type}):"
            echo "  - Total Samples: ${total_samples} (${successful_samples} ok, ${failed_samples} failed)"
            echo "  - Throughput: ${throughput} req/sec"
            echo "  - Error Rate: ${error_rate}%"
            echo "  - Avg Response Time: ${avg_response_time} ms"
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
    echo -e "  ${CYAN}Throughput:${NC} ${GREEN}$throughput${NC} req/sec"
    echo -e "  ${CYAN}Error Rate:${NC} ${RED}$error_rate${NC} %"
    echo -e "  ${CYAN}Avg Response Time:${NC} ${YELLOW}$avg_response_time${NC} ms"
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
    local users=$1 duration=$2 payload=$3 test_type=$4 description=$5 summary_file=${6:-""}
    local payload_file="${payload}.json"
    local jtl_file
    jtl_file=$(create_jtl_filename "$users" "$payload_file" "$test_type")
    local log_file="${LOG_DIR}/${test_type}_${users}users_${payload}_${TIMESTAMP}.log"

    print_progress "$description"
    echo -e "  ${CYAN}Users:${NC} $users | ${CYAN}Duration:${NC} $duration seconds | ${CYAN}Payload:${NC} $payload"
    print_info "Live JMeter output:"
    echo -e "${YELLOW}===========================================${NC}"

    run_with_tee "$log_file" "$JMETER_PATH" -n -t "$TEST_PLAN" \
        -Jusers="$users" \
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
        generate_summary_report "$jtl_file" "$users" "$payload" "$test_type" "$summary_file"
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
        # Block until resume writes to the FIFO
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
validate_positive_integers "user counts" "${USER_COUNTS[@]}"

TOTAL_SCENARIOS=$(( ${#PAYLOADS[@]} * ${#USER_COUNTS[@]} ))

print_info "Scenario Matrix (${TOTAL_SCENARIOS} scenarios — outer: payloads, inner: users):"
scenario_idx=0
for P in "${PAYLOADS[@]}"; do
    for U in "${USER_COUNTS[@]}"; do
        scenario_idx=$((scenario_idx + 1))
        WU=$(compute_warmup_users "$U")
        echo -e "  ${PURPLE}[$scenario_idx/$TOTAL_SCENARIOS]${NC} ${CYAN}$U users${NC} x ${CYAN}$P${NC} | warmup: $WU users, ${WARMUP_DURATION}s | test: $U users, ${DURATION}s"
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
    echo "Users: ${USER_COUNTS[*]} | Payloads: ${PAYLOADS[*]}"
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
    for USERS in "${USER_COUNTS[@]}"; do
        CURRENT_SCENARIO=$((CURRENT_SCENARIO + 1))
        WARMUP_USERS=$(compute_warmup_users "$USERS")

        print_header "SCENARIO $CURRENT_SCENARIO OF $TOTAL_SCENARIOS: ${USERS} users x ${PAYLOAD}"

        # ── Warmup ────────────────────────────────────────────────────────────
        print_header "  WARMUP"
        if run_jmeter_test "$WARMUP_USERS" "$WARMUP_DURATION" "$PAYLOAD" "warmup" \
                "Warmup: ${WARMUP_USERS} users for ${WARMUP_DURATION}s with ${PAYLOAD} payload" "$SUMMARY_FILE"; then
            echo "Scenario $CURRENT_SCENARIO Warmup - SUCCESS" >> "$SUMMARY_FILE"
        else
            echo "Scenario $CURRENT_SCENARIO Warmup - FAILED" >> "$SUMMARY_FILE"
            print_warning "Warmup failed, continuing with main test..."
        fi

        print_info "Warmup cooldown (${WARMUP_COOLDOWN} seconds)..."
        show_progress $WARMUP_COOLDOWN

        # ── Main test ─────────────────────────────────────────────────────────
        print_header "  LOAD TEST"
        if run_jmeter_test "$USERS" "$DURATION" "$PAYLOAD" "loadtest" \
                "Load test: ${USERS} users, ${PAYLOAD} payload, ${DURATION}s" "$SUMMARY_FILE"; then
            echo "Scenario $CURRENT_SCENARIO LoadTest ${USERS} users ${PAYLOAD} - SUCCESS" >> "$SUMMARY_FILE"
        else
            echo "Scenario $CURRENT_SCENARIO LoadTest ${USERS} users ${PAYLOAD} - FAILED" >> "$SUMMARY_FILE"
        fi

        # ── Pause for service restart (skip after last scenario) ──────────────
        if [ $CURRENT_SCENARIO -lt $TOTAL_SCENARIOS ]; then
            pause_for_restart "$CURRENT_SCENARIO" "$TOTAL_SCENARIOS"
        fi
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
