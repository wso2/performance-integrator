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

# Script to generate payload files with JSON format
# Payloads: 1KB, 10KB, 50KB, 100KB, 250KB, 1MB

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOADS_DIR="$SCRIPT_DIR"

# Colors for output
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${CYAN}Generating payload files...${NC}"
echo ""

# Create payloads directory if it doesn't exist
if [ ! -d "$PAYLOADS_DIR" ]; then
    echo -e "${YELLOW}Creating payloads directory: $PAYLOADS_DIR${NC}"
    mkdir -p "$PAYLOADS_DIR"
fi

# Function to generate random alphanumeric string
generate_random_string() {
    local length=$1
    LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w "$length" | head -n 1
}

# Function to create JSON payload file
create_payload() {
    local size_kb=$1
    local filename="${size_kb}KB.txt"
    local filepath="$PAYLOADS_DIR/$filename"
    
    # Calculate target size in bytes
    local target_bytes=$((size_kb * 1024))
    
    # JSON structure overhead (approximately): {"message":"..."}
    local json_overhead=15
    
    # Calculate message content size
    local message_size=$((target_bytes - json_overhead))
    
    # Ensure message size is positive
    if [ $message_size -lt 1 ]; then
        message_size=1
    fi
    
    echo -e "${YELLOW}Generating $filename (target: ${size_kb}KB)...${NC}"
    
    # Generate random message content
    local message=$(generate_random_string $message_size)
    
    # Create JSON file
    echo "{\"message\":\"$message\"}" > "$filepath"
    
    # Get actual file size
    local actual_size=$(stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath" 2>/dev/null)
    local actual_kb=$((actual_size / 1024))
    
    echo -e "${GREEN}✓ Created $filename (actual size: ${actual_kb}KB / ${actual_size} bytes)${NC}"
    echo ""
}

# Function to create a named payload file (for non-standard sizes like 1MB)
create_named_payload() {
    local size_kb=$1
    local name=$2
    local filepath="$PAYLOADS_DIR/${name}.txt"

    local target_bytes=$((size_kb * 1024))
    local json_overhead=15
    local message_size=$((target_bytes - json_overhead))

    if [ $message_size -lt 1 ]; then
        message_size=1
    fi

    echo -e "${YELLOW}Generating ${name}.txt (target: ${size_kb}KB)...${NC}"

    local message=$(generate_random_string $message_size)
    echo "{\"message\":\"$message\"}" > "$filepath"

    local actual_size=$(stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath" 2>/dev/null)
    local actual_kb=$((actual_size / 1024))

    echo -e "${GREEN}✓ Created ${name}.txt (actual size: ${actual_kb}KB / ${actual_size} bytes)${NC}"
    echo ""
}

# Generate all payload files
create_payload 1
create_payload 10
create_payload 50
create_payload 100
create_payload 250
create_named_payload 1024 "1MB"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}All payload files generated successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${CYAN}Payload files location:${NC} $PAYLOADS_DIR"
echo ""
echo -e "${CYAN}Generated files:${NC}"
ls -lh "$PAYLOADS_DIR"/*.txt 2>/dev/null | awk '{print "  " $9 " - " $5}'

echo ""
echo -e "${CYAN}Verify JSON format:${NC}"
for file in "$PAYLOADS_DIR"/*.txt; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        # Check if file is valid JSON (just show first 100 chars)
        echo -e "  ${YELLOW}$filename:${NC} $(head -c 100 "$file")..."
    fi
done
