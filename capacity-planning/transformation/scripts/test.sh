#!/bin/bash
# Transformation scenario – capacity planning (constant-throughput RPS testing).
# Required env vars: DOMAIN, AUTH_HEADER
# Example:
#   export DOMAIN="your.domain.com"
#   export AUTH_HEADER="Bearer your_token"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../scripts/common.sh"

PAYLOADS_DIR="$SCRIPT_DIR/../../../payloads/transformation"
JMETER_PATH="$SCRIPT_DIR/../apache-jmeter-5.6.3/bin/jmeter"
TEST_PLAN="$SCRIPT_DIR/test.jmx"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="$SCRIPT_DIR/logs/${TIMESTAMP}"
RESULTS_DIR="$SCRIPT_DIR/results/${TIMESTAMP}"

# ── Defaults ──────────────────────────────────────────────────────────────────
DEFAULT_DURATION=600
DEFAULT_COOLDOWN=120
DEFAULT_PAYLOADS=("1KB" "10KB" "50KB" "100KB")
DEFAULT_RPS_TARGETS=(10 50 100 200 500 1000 2000 5000)
DEFAULT_THREAD_COUNTS=(10 50 100 500)

WARMUP_DURATION=120
WARMUP_RPS=10
WARMUP_THREADS=10
WARMUP_PAYLOAD="1KB"

DURATION=$DEFAULT_DURATION
COOLDOWN=$DEFAULT_COOLDOWN
PAYLOADS=("${DEFAULT_PAYLOADS[@]}")
RPS_TARGETS=("${DEFAULT_RPS_TARGETS[@]}")
THREAD_COUNTS=("${DEFAULT_THREAD_COUNTS[@]}")
BACKGROUND_MODE=false
DRY_RUN=false

# ── Usage ─────────────────────────────────────────────────────────────────────
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --rps RPS_LIST            Comma-separated list of target RPS (e.g., 50,100,200)"
    echo "  -p, --payloads PAYLOAD_LIST   Comma-separated list of payloads (e.g., 1KB,10KB)"
    echo "  -t, --threads THREAD_LIST     Comma-separated list of concurrent connections (e.g., 10,50,100)"
    echo "  -d, --duration SECONDS        Test duration in seconds (default: $DEFAULT_DURATION)"
    echo "  -c, --cooldown SECONDS        Cooldown period between tests in seconds (default: $DEFAULT_COOLDOWN)"
    echo "  -b, --background              Run in background mode (survives SSH disconnection)"
    echo "  -n, --dry-run                 Show test execution order without running tests"
    echo "  -h, --help                    Show this help message"
    echo ""
    echo "Available payloads: 1KB, 10KB, 50KB, 100KB"
    echo "Default RPS targets: ${DEFAULT_RPS_TARGETS[*]}"
    echo "Default thread counts: ${DEFAULT_THREAD_COUNTS[*]}"
    exit "${1:-1}"
}

# ── Argument parsing ──────────────────────────────────────────────────────────
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--rps)
                [[ -z "$2" ]] && { print_error "--rps requires an argument"; show_usage; }
                IFS=',' read -ra RPS_TARGETS <<< "$2"; shift 2 ;;
            -p|--payloads)
                [[ -z "$2" ]] && { print_error "--payloads requires an argument"; show_usage; }
                IFS=',' read -ra PAYLOADS <<< "$2"; shift 2 ;;
            -t|--threads)
                [[ -z "$2" ]] && { print_error "--threads requires an argument"; show_usage; }
                IFS=',' read -ra THREAD_COUNTS <<< "$2"; shift 2 ;;
            -d|--duration)
                [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]] && { print_error "--duration requires a positive integer"; show_usage; }
                DURATION=$2; shift 2 ;;
            -c|--cooldown)
                [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]] && { print_error "--cooldown requires a positive integer"; show_usage; }
                COOLDOWN=$2; shift 2 ;;
            -b|--background) BACKGROUND_MODE=true; shift ;;
            -n|--dry-run)    DRY_RUN=true; shift ;;
            -h|--help)       show_usage 0 ;;
            *) print_error "Unknown option: $1"; show_usage ;;
        esac
    done
}

# ── Payload validation (JSON .json files) ─────────────────────────────────────
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
    local payload_file="${payload}.json"
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

# ── Main ──────────────────────────────────────────────────────────────────────
parse_arguments "$@"
handle_background_mode "$@"

if ! mkdir -p "$LOG_DIR" "$RESULTS_DIR"; then
    print_error "Failed to create directories $LOG_DIR and $RESULTS_DIR"
    exit 1
fi

if [ "$DRY_RUN" = true ]; then
    print_header "DRY RUN MODE - TEST EXECUTION PREVIEW"
else
    print_header "LOAD TEST INITIALIZATION"
fi

print_info "Validating arguments..."
validate_payloads
validate_positive_integers "RPS targets" "${RPS_TARGETS[@]}"
validate_positive_integers "thread counts" "${THREAD_COUNTS[@]}"

print_info "Test Configuration:"
echo -e "  ${CYAN}Duration:${NC} $DURATION seconds | ${CYAN}Cooldown:${NC} $COOLDOWN seconds"
echo -e "  ${CYAN}Target RPS:${NC} ${RPS_TARGETS[*]}"
echo -e "  ${CYAN}Concurrent Connections:${NC} ${THREAD_COUNTS[*]}"
echo -e "  ${CYAN}Payloads:${NC} ${PAYLOADS[*]}"
echo ""

if [ "$DRY_RUN" = false ]; then
    print_info "Checking environment variables..."
    [[ -z "$DOMAIN" ]] && { print_error "DOMAIN is not set. Example: export DOMAIN=\"your.domain.com\""; exit 1; }
    [[ -z "$AUTH_HEADER" ]] && { print_error "AUTH_HEADER is not set. Example: export AUTH_HEADER=\"Bearer token\""; exit 1; }

    print_info "Checking JMeter installation..."
    [[ ! -f "$JMETER_PATH" ]] && { print_error "JMeter not found at: $JMETER_PATH"; exit 1; }
    [[ ! -f "$TEST_PLAN" ]]   && { print_error "Test plan not found: $TEST_PLAN"; exit 1; }
fi

print_success "Validation completed"
echo ""

SUMMARY_FILE="${RESULTS_DIR}/test_summary_${TIMESTAMP}.txt"
{
    echo "Load Test Summary - $(date)"
    echo "Domain: $DOMAIN"
    echo "Test Type: Constant Throughput Testing"
    echo "Duration: $DURATION seconds | Cooldown: $COOLDOWN seconds"
    echo "Target RPS: ${RPS_TARGETS[*]}"
    echo "Concurrent Connections: ${THREAD_COUNTS[*]}"
    echo "Payloads: ${PAYLOADS[*]}"
    echo "Warmup: $WARMUP_RPS RPS with $WARMUP_THREADS threads for $WARMUP_DURATION seconds"
    echo "==========================================="
    echo ""
} > "$SUMMARY_FILE"

TOTAL_TESTS=$((${#PAYLOADS[@]} * ${#RPS_TARGETS[@]} * ${#THREAD_COUNTS[@]} + 1))
CURRENT_TEST=0

# ── Warmup ────────────────────────────────────────────────────────────────────
print_header "STARTING WARMUP RUN"
CURRENT_TEST=$((CURRENT_TEST + 1))
echo -e "${PURPLE}Test $CURRENT_TEST of $TOTAL_TESTS${NC}"

if [ "$DRY_RUN" = true ]; then
    print_info "[DRY RUN] Would run warmup: $WARMUP_RPS RPS, $WARMUP_THREADS threads, ${WARMUP_DURATION}s, $WARMUP_PAYLOAD"
    echo ""
else
    if run_jmeter_test "$WARMUP_RPS" "$WARMUP_THREADS" "$WARMUP_DURATION" "$WARMUP_PAYLOAD" "warmup" \
            "Warmup run with ${WARMUP_RPS} RPS and ${WARMUP_THREADS} threads for ${WARMUP_DURATION} seconds" "$SUMMARY_FILE"; then
        echo "Warmup - SUCCESS" >> "$SUMMARY_FILE"
        print_info "Warmup cooldown (30 seconds)..."
        show_progress 30
    else
        echo "Warmup - FAILED" >> "$SUMMARY_FILE"
        print_warning "Warmup failed, continuing with main tests..."
    fi
fi

# ── Main load tests ───────────────────────────────────────────────────────────
print_header "STARTING MAIN LOAD TESTS"

for RPS in "${RPS_TARGETS[@]}"; do
    for PAYLOAD in "${PAYLOADS[@]}"; do
        for THREADS in "${THREAD_COUNTS[@]}"; do
            CURRENT_TEST=$((CURRENT_TEST + 1))
            echo -e "${PURPLE}Test $CURRENT_TEST of $TOTAL_TESTS${NC}"

            if [ "$DRY_RUN" = true ]; then
                print_info "[DRY RUN] Would run: $RPS RPS, $THREADS threads, ${DURATION}s, $PAYLOAD"
                echo ""
            else
                if run_jmeter_test "$RPS" "$THREADS" "$DURATION" "$PAYLOAD" "loadtest" \
                        "Constant throughput test: ${RPS} RPS, ${THREADS} threads, ${PAYLOAD} payload" "$SUMMARY_FILE"; then
                    echo "LoadTest ${RPS} RPS ${THREADS} threads ${PAYLOAD} - SUCCESS" >> "$SUMMARY_FILE"
                else
                    echo "LoadTest ${RPS} RPS ${THREADS} threads ${PAYLOAD} - FAILED" >> "$SUMMARY_FILE"
                fi

                if [ $CURRENT_TEST -lt $TOTAL_TESTS ]; then
                    print_info "Cooldown (${COOLDOWN} seconds)..."
                    show_progress $COOLDOWN
                fi
            fi
        done
    done
done

if [ "$DRY_RUN" = true ]; then
    print_header "DRY RUN COMPLETED"
    print_success "Total tests that would be executed: $TOTAL_TESTS"
    exit 0
fi

print_header "ALL LOAD TESTS COMPLETED"

{
    echo ""
    echo "Test completed at: $(date)"
    echo "Total tests run: $TOTAL_TESTS"
    echo ""
    echo "Reports: $RESULTS_DIR/*_summary_*.txt"
    echo "Logs:    $LOG_DIR/*.log"
} >> "$SUMMARY_FILE"

print_success "All load tests completed!"
print_info "Summary: $SUMMARY_FILE"
print_info "Results: $RESULTS_DIR"
