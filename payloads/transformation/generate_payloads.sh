#!/bin/bash
# Generate JSON payload files for the transformation scenario.
# The transformation service expects: {"payload": <json-object>}
# Sizes: 1KB, 10KB, 50KB, 100KB

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOADS_DIR="$SCRIPT_DIR"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}Generating JSON payload files for transformation scenario...${NC}"
echo ""

generate_random_string() {
    local length=$1
    LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w "$length" | head -n 1
}

# Creates a JSON file of approximately size_kb kilobytes.
# Structure: {"payload":{"data":"<random-string>"}}
create_payload() {
    local size_kb=$1
    local filepath="$PAYLOADS_DIR/${size_kb}KB.json"
    local target_bytes=$((size_kb * 1024))

    # Wrapper overhead: {"payload":{"data":""}} = 22 chars
    local wrapper_overhead=22
    local data_size=$((target_bytes - wrapper_overhead))
    [[ $data_size -lt 1 ]] && data_size=1

    echo -e "${YELLOW}Generating ${size_kb}KB.json (target: ${size_kb}KB)...${NC}"
    local data
    data=$(generate_random_string "$data_size")
    echo "{\"payload\":{\"data\":\"$data\"}}" > "$filepath"

    local actual_size
    actual_size=$(stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath" 2>/dev/null)
    local actual_kb=$((actual_size / 1024))
    echo -e "${GREEN}Created ${size_kb}KB.json (actual: ${actual_kb}KB / ${actual_size} bytes)${NC}"
    echo ""
}

create_payload 1
create_payload 10
create_payload 50
create_payload 100

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}All payload files generated successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}Payload files location:${NC} $PAYLOADS_DIR"
echo ""
echo -e "${CYAN}Generated files:${NC}"
ls -lh "$PAYLOADS_DIR"/*.json 2>/dev/null | awk '{print "  " $9 " - " $5}'
