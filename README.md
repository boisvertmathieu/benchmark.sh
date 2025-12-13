# API Benchmark Tool

A generic shell script to compare the performance of two paginated API endpoints.

## Features

- Single request latency (avg, p50, p95, min, max)
- Response size comparison
- Full pagination traversal timing
- Formatted console report with improvement percentages

## Requirements

- `curl`
- `jq`
- `awk`

## Usage

```bash
ENDPOINT_A='/api/items?page=0&size=100' \
ENDPOINT_B='/api/items/stream?size=100' \
ENDPOINT_A_NAME='HATEOAS' \
ENDPOINT_B_NAME='Stream' \
./api-benchmark.sh
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BASE_URL` | Base URL of the API | `http://localhost:8080` |
| `ENDPOINT_A` | First endpoint path (with metadata) | *required* |
| `ENDPOINT_B` | Second endpoint path (optimized) | *required* |
| `ENDPOINT_A_NAME` | Display name for endpoint A | `Endpoint A` |
| `ENDPOINT_B_NAME` | Display name for endpoint B | `Endpoint B` |
| `PAGE_SIZE` | Items per page | `100` |
| `WARMUP_REQUESTS` | Number of warmup requests | `5` |
| `BENCHMARK_REQUESTS` | Number of benchmark iterations | `20` |
| `JQ_COUNT_A` | jq expression to count items in A | `'._embedded \| to_entries[0].value \| length // 0'` |
| `JQ_COUNT_B` | jq expression to count items in B | `'length'` |
| `JQ_HAS_NEXT_A` | jq expression to check next page in A | `'._links.next // empty'` |
| `JQ_CURSOR_B` | jq expression to get cursor from B | `'.[-1].id // 0'` |
| `PAGE_PARAM_A` | Page parameter name for A | `page` |
| `CURSOR_PARAM_B` | Cursor parameter name for B | `afterId` |
