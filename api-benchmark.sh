#!/usr/bin/env bash
#
# API Endpoint Performance Benchmark
# A generic, customizable tool to compare two paginated API endpoints
#
# Usage:
#   ./api-benchmark.sh
#
# Environment variables:
#   BASE_URL              - Base URL of the API (default: http://localhost:8080)
#   ENDPOINT_A            - First endpoint URL relative path (with metadata, e.g., HATEOAS)
#   ENDPOINT_B            - Second endpoint URL relative path (optimized/stream)
#   ENDPOINT_A_NAME       - Display name for endpoint A (default: "Endpoint A")
#   ENDPOINT_B_NAME       - Display name for endpoint B (default: "Endpoint B")
#   PAGE_SIZE             - Number of items per page (default: 100)
#   WARMUP_REQUESTS       - Number of warmup requests (default: 5)
#   BENCHMARK_REQUESTS    - Number of benchmark requests (default: 20)
#
# Pagination configuration:
#   JQ_COUNT_A            - jq expression to count items in endpoint A response
#   JQ_COUNT_B            - jq expression to count items in endpoint B response
#   JQ_HAS_NEXT_A         - jq expression to check if endpoint A has next page
#   PAGE_PARAM_A          - Page parameter name for endpoint A (default: "page")
#   PAGE_PARAM_B          - Page parameter name for endpoint B (default: "page")
#
# Examples:
#
#   # HATEOAS vs Stream comparison (both use page-based pagination)
#   BASE_URL="http://localhost:8080" \
#   ENDPOINT_A="/api/items?size=100" \
#   ENDPOINT_B="/api/items/stream?size=100" \
#   ENDPOINT_A_NAME="HATEOAS" \
#   ENDPOINT_B_NAME="Stream" \
#   JQ_COUNT_A="._embedded.items | length // 0" \
#   JQ_COUNT_B="length" \
#   JQ_HAS_NEXT_A="._links.next // empty" \
#   PAGE_PARAM_A="page" \
#   PAGE_PARAM_B="page" \
#   ./api-benchmark.sh
#
#   # Simple paginated API comparison
#   BASE_URL="https://api.example.com" \
#   ENDPOINT_A="/v1/users?limit=50" \
#   ENDPOINT_B="/v2/users?limit=50" \
#   ENDPOINT_A_NAME="API v1" \
#   ENDPOINT_B_NAME="API v2" \
#   JQ_COUNT_A=".data | length // 0" \
#   JQ_COUNT_B=".data | length // 0" \
#   JQ_HAS_NEXT_A=".pagination.next // empty" \
#   PAGE_PARAM_A="page" \
#   PAGE_PARAM_B="page" \
#   ./api-benchmark.sh
#

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
BASE_URL="${BASE_URL:-http://localhost:8080}"
ENDPOINT_A="${ENDPOINT_A:-}"
ENDPOINT_B="${ENDPOINT_B:-}"
ENDPOINT_A_NAME="${ENDPOINT_A_NAME:-Endpoint A}"
ENDPOINT_B_NAME="${ENDPOINT_B_NAME:-Endpoint B}"
PAGE_SIZE="${PAGE_SIZE:-100}"
WARMUP_REQUESTS="${WARMUP_REQUESTS:-5}"
BENCHMARK_REQUESTS="${BENCHMARK_REQUESTS:-20}"

# jq expressions for parsing responses (customize for your API)
JQ_COUNT_A="${JQ_COUNT_A:-._embedded | to_entries[0].value | length // 0}"
JQ_COUNT_B="${JQ_COUNT_B:-length}"
JQ_HAS_NEXT_A="${JQ_HAS_NEXT_A:-._links.next // empty}"
PAGE_PARAM_A="${PAGE_PARAM_A:-page}"
PAGE_PARAM_B="${PAGE_PARAM_B:-page}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# =============================================================================
# Usage and Validation
# =============================================================================
print_usage() {
    echo -e "${BOLD}API Endpoint Performance Benchmark${NC}"
    echo ""
    echo "Usage:"
    echo "  ENDPOINT_A='/api/items?size=100' \\"
    echo "  ENDPOINT_B='/api/items/stream?size=100' \\"
    echo "  ./api-benchmark.sh"
    echo ""
    echo "Required environment variables:"
    echo "  ENDPOINT_A          - First endpoint URL (relative path)"
    echo "  ENDPOINT_B          - Second endpoint URL (relative path)"
    echo ""
    echo "Optional environment variables:"
    echo "  BASE_URL            - API base URL (default: http://localhost:8080)"
    echo "  ENDPOINT_A_NAME     - Display name for endpoint A (default: Endpoint A)"
    echo "  ENDPOINT_B_NAME     - Display name for endpoint B (default: Endpoint B)"
    echo "  PAGE_SIZE           - Items per page (default: 100)"
    echo "  WARMUP_REQUESTS     - Warmup request count (default: 5)"
    echo "  BENCHMARK_REQUESTS  - Benchmark request count (default: 20)"
    echo ""
    echo "Pagination configuration:"
    echo "  JQ_COUNT_A          - jq expr to count items in endpoint A"
    echo "  JQ_COUNT_B          - jq expr to count items in endpoint B"
    echo "  JQ_HAS_NEXT_A       - jq expr to check if endpoint A has next page"
    echo "  PAGE_PARAM_A        - Page parameter name for endpoint A"
    echo "  PAGE_PARAM_B        - Page parameter name for endpoint B"
}

if [[ -z "$ENDPOINT_A" ]] || [[ -z "$ENDPOINT_B" ]]; then
    echo -e "${RED}ERROR: ENDPOINT_A and ENDPOINT_B must be set${NC}"
    echo ""
    print_usage
    exit 1
fi

# =============================================================================
# Temp files for results
# =============================================================================
A_TIMES=$(mktemp)
B_TIMES=$(mktemp)

cleanup() {
    rm -f "$A_TIMES" "$B_TIMES" /tmp/a_response.json /tmp/b_response.json
}
trap cleanup EXIT

# =============================================================================
# Header
# =============================================================================
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${BLUE}                    API ENDPOINT BENCHMARK                          ${NC}"
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}Endpoints:${NC}"
echo -e "  A: ${ENDPOINT_A_NAME} (${ENDPOINT_A})"
echo -e "  B: ${ENDPOINT_B_NAME} (${ENDPOINT_B})"
echo ""

# =============================================================================
# Check dependencies
# =============================================================================
echo -e "${CYAN}[1/5]${NC} Checking dependencies..."
MISSING_DEPS=()

if ! command -v curl &> /dev/null; then
    MISSING_DEPS+=("curl")
fi

if ! command -v jq &> /dev/null; then
    MISSING_DEPS+=("jq")
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo -e "${RED}ERROR: Missing required dependencies: ${MISSING_DEPS[*]}${NC}"
    exit 1
fi

# Check if server is running
if ! curl -s --fail "${BASE_URL}${ENDPOINT_B}" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Server not responding at ${BASE_URL}${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Server is running at ${BASE_URL}${NC}"
echo ""

# =============================================================================
# Warmup phase
# =============================================================================
echo -e "${CYAN}[2/5]${NC} Warming up (${WARMUP_REQUESTS} requests each)..."
for ((i=1; i<=WARMUP_REQUESTS; i++)); do
    curl -s "${BASE_URL}${ENDPOINT_A}" > /dev/null
    curl -s "${BASE_URL}${ENDPOINT_B}" > /dev/null
done
echo -e "${GREEN}✓ Warmup complete${NC}"
echo ""

# =============================================================================
# Benchmark request latency while iterating through pages
# =============================================================================
echo -e "${CYAN}[3/5]${NC} Benchmarking request latency across pages..."

# Endpoint A: iterate through pages
a_page=0
a_requests=0
while [[ $a_requests -lt $BENCHMARK_REQUESTS ]]; do
    # Build URL with page parameter
    if [[ "$ENDPOINT_A" == *"?"* ]]; then
        url="${BASE_URL}${ENDPOINT_A}&${PAGE_PARAM_A}=${a_page}"
    else
        url="${BASE_URL}${ENDPOINT_A}?${PAGE_PARAM_A}=${a_page}"
    fi
    
    time_ms=$(curl -s -o /tmp/a_response.json -w "%{time_total}" "$url" | awk '{printf "%.2f", $1 * 1000}')
    echo "$time_ms" >> "$A_TIMES"
    a_requests=$((a_requests + 1))
    
    # Check if more pages exist
    count=$(jq -r "${JQ_COUNT_A}" /tmp/a_response.json 2>/dev/null | tr -d '\n' || echo "0")
    # Ensure count is numeric
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    has_next=$(jq -r "${JQ_HAS_NEXT_A}" /tmp/a_response.json 2>/dev/null)
    if [[ -z "$has_next" ]] || [[ "$count" -lt "$PAGE_SIZE" ]]; then
        a_page=0  # Restart from first page if we reach the end
    else
        a_page=$((a_page + 1))
    fi
done

# Endpoint B: iterate through pages (now uses page-based pagination)
b_page=0
b_requests=0
while [[ $b_requests -lt $BENCHMARK_REQUESTS ]]; do
    # Build URL with page parameter
    if [[ "$ENDPOINT_B" == *"?"* ]]; then
        url="${BASE_URL}${ENDPOINT_B}&${PAGE_PARAM_B}=${b_page}"
    else
        url="${BASE_URL}${ENDPOINT_B}?${PAGE_PARAM_B}=${b_page}"
    fi
    
    time_ms=$(curl -s -o /tmp/b_response.json -w "%{time_total}" "$url" | awk '{printf "%.2f", $1 * 1000}')
    echo "$time_ms" >> "$B_TIMES"
    b_requests=$((b_requests + 1))
    
    # Check if more pages exist
    count=$(jq "${JQ_COUNT_B}" /tmp/b_response.json 2>/dev/null | tr -d '\n' || echo "0")
    # Ensure count is numeric
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    if [[ "$count" -eq 0 ]] || [[ "$count" -lt "$PAGE_SIZE" ]]; then
        b_page=0  # Restart from first page if we reach the end
    else
        b_page=$((b_page + 1))
    fi
done

rm -f /tmp/a_response.json /tmp/b_response.json

echo -e "${GREEN}✓ Latency benchmark complete${NC}"
echo ""

# =============================================================================
# Measure response sizes
# =============================================================================
echo -e "${CYAN}[4/5]${NC} Measuring response sizes..."

a_size=$(curl -s "${BASE_URL}${ENDPOINT_A}" | wc -c)
b_size=$(curl -s "${BASE_URL}${ENDPOINT_B}" | wc -c)

echo -e "${GREEN}✓ Size measurement complete${NC}"
echo ""

# =============================================================================
# Pagination traversal benchmark
# =============================================================================
echo -e "${CYAN}[5/5]${NC} Benchmarking full pagination traversal..."

# Endpoint A: offset-based pagination
a_start=$(date +%s.%N)
a_page=0
a_total_items=0
while true; do
    # Build URL with page parameter
    if [[ "$ENDPOINT_A" == *"?"* ]]; then
        url="${BASE_URL}${ENDPOINT_A}&${PAGE_PARAM_A}=${a_page}"
    else
        url="${BASE_URL}${ENDPOINT_A}?${PAGE_PARAM_A}=${a_page}"
    fi
    response=$(curl -s "$url")
    count=$(echo "$response" | jq -r "${JQ_COUNT_A}" 2>/dev/null | tr -d '\n' || echo "0")
    # Ensure count is numeric
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    a_total_items=$((a_total_items + count))
    
    # Check if this is the last page
    has_next=$(echo "$response" | jq -r "${JQ_HAS_NEXT_A}" 2>/dev/null || echo "")
    if [[ -z "$has_next" ]] || [[ "$count" -lt "$PAGE_SIZE" ]]; then
        break
    fi
    a_page=$((a_page + 1))
done
a_end=$(date +%s.%N)
a_traversal_time=$(awk "BEGIN {printf \"%.2f\", $a_end - $a_start}")
a_pages=$((a_page + 1))

# Endpoint B: page-based pagination
b_start=$(date +%s.%N)
b_page=0
b_total_items=0
b_pages=0
while true; do
    # Build URL with page parameter
    if [[ "$ENDPOINT_B" == *"?"* ]]; then
        url="${BASE_URL}${ENDPOINT_B}&${PAGE_PARAM_B}=${b_page}"
    else
        url="${BASE_URL}${ENDPOINT_B}?${PAGE_PARAM_B}=${b_page}"
    fi
    response=$(curl -s "$url")
    count=$(echo "$response" | jq "${JQ_COUNT_B}" 2>/dev/null | tr -d '\n' || echo "0")
    # Ensure count is numeric
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
    
    if [[ "$count" -eq 0 ]]; then
        break
    fi
    
    b_total_items=$((b_total_items + count))
    b_pages=$((b_pages + 1))
    
    if [[ "$count" -lt "$PAGE_SIZE" ]]; then
        break
    fi
    b_page=$((b_page + 1))
done
b_end=$(date +%s.%N)
b_traversal_time=$(awk "BEGIN {printf \"%.2f\", $b_end - $b_start}")

echo -e "${GREEN}✓ Pagination traversal complete${NC}"
echo ""

# =============================================================================
# Calculate statistics
# =============================================================================
calc_stats() {
    local file=$1
    awk '{
        sum += $1;
        values[NR] = $1;
        count++;
    }
    END {
        avg = sum / count;
        
        # Sort for percentiles
        n = asort(values);
        p50_idx = int(n * 0.50);
        p95_idx = int(n * 0.95);
        if (p50_idx < 1) p50_idx = 1;
        if (p95_idx < 1) p95_idx = 1;
        
        printf "%.2f %.2f %.2f %.2f %.2f", values[1], values[n], avg, values[p50_idx], values[p95_idx];
    }' "$file"
}

a_stats=$(calc_stats "$A_TIMES")
b_stats=$(calc_stats "$B_TIMES")

read a_min a_max a_avg a_p50 a_p95 <<< "$a_stats"
read b_min b_max b_avg b_p50 b_p95 <<< "$b_stats"

# Calculate improvements
latency_improvement=$(awk "BEGIN {printf \"%.1f\", (1 - $b_avg / $a_avg) * 100}")
size_improvement=$(awk "BEGIN {printf \"%.1f\", (1 - $b_size / $a_size) * 100}")
traversal_improvement=$(awk "BEGIN {printf \"%.1f\", (1 - $b_traversal_time / $a_traversal_time) * 100}")

# =============================================================================
# Print report
# =============================================================================
echo ""
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${BLUE}                    PERFORMANCE BENCHMARK REPORT                     ${NC}"
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}Configuration:${NC} Page Size: ${PAGE_SIZE} items | Requests: ${BENCHMARK_REQUESTS}"
echo ""
echo -e "${BOLD}${CYAN}SINGLE REQUEST LATENCY (ms)${NC}"
echo "────────────────────────────────────────────────────────────────────"
printf "  %-14s  %10s  %10s  %12s\n" "Metric" "${ENDPOINT_A_NAME:0:10}" "${ENDPOINT_B_NAME:0:10}" "Improvement"
echo "  ──────────────  ──────────  ──────────  ────────────"
printf "  %-14s  %10.2f  %10.2f  ${GREEN}%+10.1f%%${NC}\n" "Average" "$a_avg" "$b_avg" "$latency_improvement"
printf "  %-14s  %10.2f  %10.2f\n" "P50 (Median)" "$a_p50" "$b_p50"
printf "  %-14s  %10.2f  %10.2f\n" "P95" "$a_p95" "$b_p95"
printf "  %-14s  %10.2f  %10.2f\n" "Min" "$a_min" "$b_min"
printf "  %-14s  %10.2f  %10.2f\n" "Max" "$a_max" "$b_max"
echo ""
echo -e "${BOLD}${CYAN}RESPONSE SIZE (bytes)${NC}"
echo "────────────────────────────────────────────────────────────────────"
printf "  %-14s  %10d  %10d  ${GREEN}%+10.1f%%${NC}\n" "Size per page" "$a_size" "$b_size" "$size_improvement"
echo ""
echo -e "${BOLD}${CYAN}FULL PAGINATION TRAVERSAL${NC}"
echo "────────────────────────────────────────────────────────────────────"
printf "  %-14s  %10d  %10d\n" "Total Items" "$a_total_items" "$b_total_items"
printf "  %-14s  %10d  %10d\n" "Pages" "$a_pages" "$b_pages"
printf "  %-14s  %9.2fs  %9.2fs  ${GREEN}%+10.1f%%${NC}\n" "Total Time" "$a_traversal_time" "$b_traversal_time" "$traversal_improvement"
echo ""
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}SUMMARY${NC}"
echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════${NC}"

# Show improvement or degradation for each metric
if awk "BEGIN {exit !($latency_improvement > 0)}"; then
    echo -e "  ${GREEN}✓${NC} Latency:   ${ENDPOINT_B_NAME} is ${GREEN}${latency_improvement}%${NC} faster"
else
    latency_abs=$(echo "$latency_improvement" | tr -d '-')
    echo -e "  ${YELLOW}⚠${NC} Latency:   ${ENDPOINT_B_NAME} is ${YELLOW}${latency_abs}%${NC} slower"
fi

if awk "BEGIN {exit !($size_improvement > 0)}"; then
    echo -e "  ${GREEN}✓${NC} Size:      ${ENDPOINT_B_NAME} responses are ${GREEN}${size_improvement}%${NC} smaller"
else
    size_abs=$(echo "$size_improvement" | tr -d '-')
    echo -e "  ${YELLOW}⚠${NC} Size:      ${ENDPOINT_B_NAME} responses are ${YELLOW}${size_abs}%${NC} larger"
fi

if awk "BEGIN {exit !($traversal_improvement > 0)}"; then
    echo -e "  ${GREEN}✓${NC} Traversal: Full scan is ${GREEN}${traversal_improvement}%${NC} faster"
else
    traversal_abs=$(echo "$traversal_improvement" | tr -d '-')
    echo -e "  ${YELLOW}⚠${NC} Traversal: Full scan is ${YELLOW}${traversal_abs}%${NC} slower"
fi

echo ""
