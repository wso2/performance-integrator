#!/bin/bash
# Passthrough scenario – performance testing (max single-replica throughput).
# Required env vars: DOMAIN, AUTH_HEADER
# Example:
#   export DOMAIN="your.domain.com"
#   export AUTH_HEADER="Bearer your_token"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../scripts/common.sh"

PAYLOADS_DIR="$SCRIPT_DIR/../../../payloads/passthrough"
JMETER_PATH="$SCRIPT_DIR/../apache-jmeter-5.6.3/bin/jmeter"
TEST_PLAN="$SCRIPT_DIR/test.jmx"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="$SCRIPT_DIR/logs/${TIMESTAMP}"
RESULTS_DIR="$SCRIPT_DIR/results/${TIMESTAMP}"

# ── Defaults ──────────────────────────────────────────────────────────────────
DEFAULT_DURATION=600
DEFAULT_COOLDOWN=180
DEFAULT_PAYLOADS=("1KB" "10KB" "50KB" "100KB" "1MB")
DEFAULT_USER_COUNTS=(100 200 500 1000)

WARMUP_DURATION=300
WARMUP_USERS=10
WARMUP_PAYLOAD="1KB"

DURATION=$DEFAULT_DURATION
COOLDOWN=$DEFAULT_COOLDOWN
PAYLOADS=("${DEFAULT_PAYLOADS[@]}")
USER_COUNTS=("${DEFAULT_USER_COUNTS[@]}")
BACKGROUND_MODE=false
DRY_RUN=false

# ── Usage ─────────────────────────────────────────────────────────────────────
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -u, --users USER_LIST        Comma-separated list of user counts (e.g., 100,200,500)"
    echo "  -p, --payloads PAYLOAD_LIST  Comma-separated list of payloads (e.g., 1KB,10KB)"
    echo "  -d, --duration SECONDS       Test duration in seconds (default: $DEFAULT_DURATION)"
    echo "  -c, --cooldown SECONDS       Cooldown period between tests in seconds (default: $DEFAULT_COOLDOWN)"
    echo "  -b, --background             Run in background mode (survives SSH disconnection)"
    echo "  -n, --dry-run                Show test execution order without running tests"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Available payloads: 1KB, 10KB, 50KB, 100KB, 250KB, 1MB"
    echo "Default users: ${DEFAULT_USER_COUNTS[*]}"
    echo "Default duration: $DEFAULT_DURATION seconds"
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

# ── Payload validation (plain-text .txt files) ────────────────────────────────
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
    local payload_file="${payload}.txt"
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
validate_positive_integers "user counts" "${USER_COUNTS[@]}"

print_info "Test Configuration:"
echo -e "  ${CYAN}Duration:${NC} $DURATION seconds | ${CYAN}Cooldown:${NC} $COOLDOWN seconds"
echo -e "  ${CYAN}Users:${NC} ${USER_COUNTS[*]} | ${CYAN}Payloads:${NC} ${PAYLOADS[*]}"
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
    echo "Duration: $DURATION seconds | Cooldown: $COOLDOWN seconds"
    echo "Users: ${USER_COUNTS[*]} | Payloads: ${PAYLOADS[*]}"
    echo "Warmup: $WARMUP_USERS users for $WARMUP_DURATION seconds"
    echo "==========================================="
    echo ""
} > "$SUMMARY_FILE"

TOTAL_TESTS=$((${#PAYLOADS[@]} * ${#USER_COUNTS[@]} + 1))
CURRENT_TEST=0

# ── Warmup ────────────────────────────────────────────────────────────────────
print_header "STARTING WARMUP RUN"
CURRENT_TEST=$((CURRENT_TEST + 1))
echo -e "${PURPLE}Test $CURRENT_TEST of $TOTAL_TESTS${NC}"

if [ "$DRY_RUN" = true ]; then
    print_info "[DRY RUN] Would run warmup: $WARMUP_USERS users, ${WARMUP_DURATION}s, $WARMUP_PAYLOAD"
    echo ""
else
    if run_jmeter_test "$WARMUP_USERS" "$WARMUP_DURATION" "$WARMUP_PAYLOAD" "warmup" \
            "Warmup run with ${WARMUP_USERS} users for ${WARMUP_DURATION} seconds" "$SUMMARY_FILE"; then
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

for PAYLOAD in "${PAYLOADS[@]}"; do
    for USERS in "${USER_COUNTS[@]}"; do
        CURRENT_TEST=$((CURRENT_TEST + 1))
        echo -e "${PURPLE}Test $CURRENT_TEST of $TOTAL_TESTS${NC}"

        if [ "$DRY_RUN" = true ]; then
            print_info "[DRY RUN] Would run: $USERS users, ${DURATION}s, $PAYLOAD"
            echo ""
        else
            if run_jmeter_test "$USERS" "$DURATION" "$PAYLOAD" "loadtest" \
                    "Load test with ${USERS} users and ${PAYLOAD} payload" "$SUMMARY_FILE"; then
                echo "LoadTest ${USERS} users ${PAYLOAD} - SUCCESS" >> "$SUMMARY_FILE"
            else
                echo "LoadTest ${USERS} users ${PAYLOAD} - FAILED" >> "$SUMMARY_FILE"
            fi

            if [ $CURRENT_TEST -lt $TOTAL_TESTS ]; then
                print_info "Cooldown (${COOLDOWN} seconds)..."
                show_progress $COOLDOWN
            fi
        fi
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
