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

# Single-scenario performance test with per-scenario warmup.
# Runs one warmup (same payload, 10% of test users) followed by one main load test.
#
# Required env vars: DOMAIN, AUTH_HEADER
# Example:
#   export DOMAIN="your.domain.com"
#   export AUTH_HEADER="Bearer your_token"
#   ./single_scenario_test.sh -u 500 -p 10KB

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
DEFAULT_WARMUP_DURATION=120
WARMUP_COOLDOWN=30

USERS=""
PAYLOAD=""
DURATION=$DEFAULT_DURATION
WARMUP_DURATION=$DEFAULT_WARMUP_DURATION
DRY_RUN=false

# ── Usage ─────────────────────────────────────────────────────────────────────
show_usage() {
    echo "Usage: $0 -u USERS -p PAYLOAD [OPTIONS]"
    echo ""
    echo "Required:"
    echo "  -u, --users USERS            Number of concurrent users"
    echo "  -p, --payload PAYLOAD        Payload size (e.g., 1KB, 10KB, 50KB, 100KB)"
    echo ""
    echo "Options:"
    echo "  -d, --duration SECONDS       Test duration in seconds (default: $DEFAULT_DURATION)"
    echo "  --warmup-duration SECONDS    Warmup duration in seconds (default: $DEFAULT_WARMUP_DURATION)"
    echo "  -n, --dry-run                Show what would run without executing"
    echo "  -h, --help                   Show this help message"
    echo ""
    echo "Available payloads: 1KB, 10KB, 50KB, 100KB"
    echo ""
    echo "Warmup: same payload, 10% of test users (minimum 10), ${DEFAULT_WARMUP_DURATION}s"
    exit "${1:-1}"
}

# ── Argument parsing ──────────────────────────────────────────────────────────
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--users)
                [[ -z "$2" ]] && { print_error "--users requires a value"; show_usage; }
                USERS=$2; shift 2 ;;
            -p|--payload)
                [[ -z "$2" ]] && { print_error "--payload requires a value"; show_usage; }
                PAYLOAD=$2; shift 2 ;;
            -d|--duration)
                [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]] && { print_error "--duration requires a positive integer"; show_usage; }
                DURATION=$2; shift 2 ;;
            --warmup-duration)
                [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]] && { print_error "--warmup-duration requires a positive integer"; show_usage; }
                WARMUP_DURATION=$2; shift 2 ;;
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

# ── Main ──────────────────────────────────────────────────────────────────────
parse_arguments "$@"

if [ "$DRY_RUN" = true ]; then
    print_header "DRY RUN MODE - SINGLE SCENARIO PREVIEW"
else
    print_header "SINGLE SCENARIO TEST INITIALIZATION"
fi

print_info "Validating arguments..."

[[ -z "$USERS" ]]   && { print_error "--users is required";   show_usage; }
[[ -z "$PAYLOAD" ]] && { print_error "--payload is required"; show_usage; }

validate_positive_integers "user count" "$USERS"

if [[ ! -f "$PAYLOADS_DIR/${PAYLOAD}.json" ]]; then
    print_error "Payload file not found: ${PAYLOADS_DIR}/${PAYLOAD}.json"
    print_info "Available payloads:"
    ls -1 "$PAYLOADS_DIR"/*.json 2>/dev/null | sed "s|$PAYLOADS_DIR/||;s/.json$//" | sed 's/^/  /'
    exit 1
fi

WARMUP_USERS=$(compute_warmup_users "$USERS")

print_info "Scenario Configuration:"
echo -e "  ${CYAN}Users:${NC} $USERS | ${CYAN}Payload:${NC} $PAYLOAD | ${CYAN}Duration:${NC} $DURATION seconds"
echo -e "  ${CYAN}Warmup Users:${NC} $WARMUP_USERS | ${CYAN}Warmup Duration:${NC} $WARMUP_DURATION seconds | ${CYAN}Warmup Cooldown:${NC} $WARMUP_COOLDOWN seconds"
echo ""

if [ "$DRY_RUN" = true ]; then
    print_info "[DRY RUN] Would run warmup:    $WARMUP_USERS users, ${WARMUP_DURATION}s, $PAYLOAD"
    print_info "[DRY RUN] Would run cooldown:  ${WARMUP_COOLDOWN}s"
    print_info "[DRY RUN] Would run load test: $USERS users, ${DURATION}s, $PAYLOAD"
    echo ""
    print_header "DRY RUN COMPLETED"
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
    echo "Single Scenario Test Summary - $(date)"
    echo "Domain: $DOMAIN"
    echo "Users: $USERS | Payload: $PAYLOAD | Duration: $DURATION seconds"
    echo "Warmup: $WARMUP_USERS users for $WARMUP_DURATION seconds (same payload)"
    echo "==========================================="
    echo ""
} > "$SUMMARY_FILE"

# ── Warmup ────────────────────────────────────────────────────────────────────
print_header "WARMUP"

if run_jmeter_test "$WARMUP_USERS" "$WARMUP_DURATION" "$PAYLOAD" "warmup" \
        "Warmup: ${WARMUP_USERS} users for ${WARMUP_DURATION}s with ${PAYLOAD} payload" "$SUMMARY_FILE"; then
    echo "Warmup - SUCCESS" >> "$SUMMARY_FILE"
else
    echo "Warmup - FAILED" >> "$SUMMARY_FILE"
    print_warning "Warmup failed, continuing with main test..."
fi

print_info "Warmup cooldown (${WARMUP_COOLDOWN} seconds)..."
show_progress $WARMUP_COOLDOWN

# ── Main load test ────────────────────────────────────────────────────────────
print_header "MAIN LOAD TEST"

if run_jmeter_test "$USERS" "$DURATION" "$PAYLOAD" "loadtest" \
        "Load test: ${USERS} users, ${PAYLOAD} payload, ${DURATION}s" "$SUMMARY_FILE"; then
    echo "LoadTest - SUCCESS" >> "$SUMMARY_FILE"
else
    echo "LoadTest - FAILED" >> "$SUMMARY_FILE"
fi

{
    echo ""
    echo "Test completed at: $(date)"
    echo ""
    echo "Reports: $RESULTS_DIR/*_summary_*.txt"
    echo "Logs:    $LOG_DIR/*.log"
} >> "$SUMMARY_FILE"

print_header "SCENARIO COMPLETED"
print_success "Single scenario test completed!"
print_info "Summary: $SUMMARY_FILE"
print_info "Results: $RESULTS_DIR"
