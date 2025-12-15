# API Benchmark Tool

A shell script to compare the performance of three endpoint implementations:
- **HATEOAS** - Traditional offset-based pagination with HATEOAS metadata
- **REST/Stream** - Optimized keyset pagination without HATEOAS overhead
- **gRPC** - Binary protocol with native streaming support

Located at: `../benchmark.sh`

## Features

- Single request latency metrics (avg, p50, p95, min, max)
- Response size comparison (bytes)
- Full pagination traversal timing
- Formatted console report with improvement percentages
- Automatic fallback if gRPC is not available

## Requirements

### Required
- `curl` - HTTP client
- `jq` - JSON processor
- `awk` - Text processing

### Optional
- `grpcurl` - gRPC command-line client (for gRPC benchmarking)

Install grpcurl:
```bash
# With Go installed
go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest

# On macOS with Homebrew
brew install grpcurl

# On Arch Linux
yay -S grpcurl
```

## Usage

### Basic Usage

From the project root:
```bash
./benchmark.sh
```

The script will automatically:
1. Check dependencies (skip gRPC if grpcurl not available)
2. Verify servers are running (HTTP on 8080, gRPC on 9090)
3. Warm up the JVM
4. Run benchmarks on all available endpoints
5. Display a comprehensive performance comparison

### Custom Configuration

```bash
# Custom page size and request count
PAGE_SIZE=200 BENCHMARK_REQUESTS=50 ./benchmark.sh

# Custom server addresses
BASE_URL='http://localhost:9000' GRPC_HOST='localhost:9091' ./benchmark.sh

# Custom date range
DATE_START="2024-06-01T00:00:00" DATE_END="2024-06-30T23:59:59" ./benchmark.sh
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BASE_URL` | Base URL for HTTP endpoints | `http://localhost:8080` |
| `GRPC_HOST` | Host and port for gRPC | `localhost:9090` |
| `PAGE_SIZE` | Items per page | `100` |
| `WARMUP_REQUESTS` | Number of warmup requests per endpoint | `5` |
| `BENCHMARK_REQUESTS` | Number of benchmark iterations | `20` |
| `DATE_START` | Start date for filtering (ISO-8601) | `2024-01-01T00:00:00` |
| `DATE_END` | End date for filtering (ISO-8601) | `2024-12-31T23:59:59` |

## Output

The benchmark produces a detailed report including:

### Single Request Latency
- Average, P50 (median), P95, Min, Max response times
- Comparison across all three endpoints

### Response Size
- Payload size in bytes for each endpoint
- Size reduction percentages

### Full Pagination Traversal
- Total items retrieved
- Number of pages traversed
- Total time to fetch all matching records
- Speed improvements

### Performance Improvements
Three comparison sections:
1. **REST/Stream vs HATEOAS** - Shows optimizations from keyset pagination
2. **gRPC vs HATEOAS** - Shows total improvements with binary protocol
3. **gRPC vs REST/Stream** - Head-to-head between optimized endpoints

## Example Output

```
╔══════════════════════════════════════════════════════════════════════╗
║       PERFORMANCE BENCHMARK: HATEOAS vs STREAM vs gRPC ENDPOINT      ║
╚══════════════════════════════════════════════════════════════════════╝

[1/6] Checking dependencies...
✓ Dependencies OK

[2/6] Checking server availability...
✓ HTTP server is running at http://localhost:8080
✓ gRPC server is running at localhost:9090

[3/6] Warming up JVM (5 requests each endpoint)...
✓ Warmup complete

[4/6] Benchmarking request latency across pages...
✓ Latency benchmark complete

[5/6] Measuring response sizes...
✓ Size measurement complete

[6/6] Benchmarking full pagination traversal...
✓ Pagination traversal complete

══════════════════════════════════════════════════════════════════════════
                       PERFORMANCE BENCHMARK REPORT
══════════════════════════════════════════════════════════════════════════

Configuration: Page Size: 100 items | Requests: 20

SINGLE REQUEST LATENCY (ms)
──────────────────────────────────────────────────────────────────────────
  Metric          HATEOAS  REST/Stream        gRPC
  ──────────────  ──────────  ──────────  ──────────
  Average             45.23       12.34        8.56
  P50 (Median)        43.11       11.89        8.12
  P95                 52.34       15.67        9.87
  Min                 38.45       10.23        7.45
  Max                 58.90       18.45       11.23

RESPONSE SIZE (bytes)
──────────────────────────────────────────────────────────────────────────
  Size per page      15234        3456        2123

FULL PAGINATION TRAVERSAL
──────────────────────────────────────────────────────────────────────────
  Total Items        10000       10000       10000
  Pages                100         100         100
  Total Time        4.52s       1.23s       0.86s

══════════════════════════════════════════════════════════════════════════
PERFORMANCE IMPROVEMENTS
══════════════════════════════════════════════════════════════════════════

REST/Stream vs HATEOAS:
  ✓ Latency:   72.7% faster
  ✓ Size:      77.3% smaller
  ✓ Traversal: 72.8% faster

gRPC vs HATEOAS:
  ✓ Latency:   81.1% faster
  ✓ Size:      86.1% smaller
  ✓ Traversal: 81.0% faster

gRPC vs REST/Stream:
  ✓ Latency:   30.6% faster
  ✓ Size:      38.6% smaller
  ✓ Traversal: 30.1% faster
```

## Troubleshooting

### grpcurl not found
If you don't have grpcurl installed, the benchmark will automatically skip gRPC testing and only compare HATEOAS vs REST/Stream.

### Server not responding
Make sure the application is running:
```bash
mvn spring-boot:run
```

The application starts:
- HTTP server on port 8080
- gRPC server on port 9090

### Permission denied
Make the script executable:
```bash
chmod +x benchmark.sh
```

## Notes

- The script uses keyset pagination for both Stream and gRPC endpoints
- All endpoints query the same dataset with the same filters
- Warmup requests ensure JIT compilation before measurements
- Statistics are calculated from multiple iterations for accuracy
- The script cleans up temporary files automatically on exit

## License

MIT
