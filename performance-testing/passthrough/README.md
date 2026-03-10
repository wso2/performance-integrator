# Performance Testing — Passthrough Scenario

## Table of Contents

- [Scenario](#scenario)
- [Architecture](#architecture)
- [Key Difference from Capacity Planning](#key-difference-from-capacity-planning)
- [Prerequisites](#prerequisites)
- [Test Execution](#test-execution)
- [Script Parameters — single_scenario_test.sh](#script-parameters--single_scenario_testsh)
- [Script Parameters — interactive_test.sh](#script-parameters--interactive_testsh)
- [Output](#output)
- [References](#references)

## Scenario

The **passthrough** scenario sends HTTP requests through the Ballerina integration service to the Netty echo backend without any transformation or business logic. This isolates the pure infrastructure overhead of the WSO2 Integration Platform PDP.

## Architecture

```txt
JMeter (EC2) → WSO2 Integration Platform NGINX → API Gateway → Ballerina Service (PDP, 1 replica) → Netty (EC2)
```

## Key Difference from Capacity Planning

Replicas are locked at **min = max = 1** in WSO2 Integration Platform (scale-to-zero disabled). Auto-scaling is intentionally disabled so results represent the throughput ceiling of a single replica, not aggregate throughput across a scaled deployment.

## Prerequisites

1. Shared assets configured — see [Passthrough Scenario](../../../scenarios/passthrough/README.md)
2. EC2 instances running (Netty backend and JMeter client)
3. `bi-svc` deployed to WSO2 Integration Platform with replica count fixed at 1 and `nettyUrl` config variable set
4. The following environment variables set on the JMeter client EC2:

| Variable | Description | Example |
| ---------- | ------------- | --------- |
| `DOMAIN` | WSO2 Integration Platform service endpoint hostname | `abc123.wso2apis.dev` |
| `AUTH_HEADER` | Authorization header value | `Bearer eyJ...` |
| `BACKEND_IP` | IP of the EC2 instance running Netty | `10.0.1.50` |

## Test Execution

### 1. Start the Netty backend on EC2

Build the backend if not already built:

```bash
cd ../../../backend && mvn clean package
```

Then start the server:

```bash
java -jar ../../../backend/target/netty-http-echo-service.jar --port 8688
```

### 2. Configure the WSO2 Integration Platform component

In the WSO2 Integration Platform console, set the replica count to **min = 1, max = 1** and disable scale-to-zero. Set the CPU/memory limits for the configuration under test, and set the `nettyUrl` config variable.

### 3. Set environment variables on the JMeter EC2

```bash
export DOMAIN="<your-wso2-integration-platform-endpoint-hostname>"
export AUTH_HEADER="Bearer <your-token>"
export BACKEND_IP="<netty-ec2-ip>"
```

### 4. Run the test

There are two scripts depending on how you want to run the tests:

**Option A — Single scenario (one `-u`/`-p` combination):**

Runs a per-scenario warmup (120s) followed by a 30s cooldown and then the main load test for the specified user count and payload size.

```bash
./scripts/single_scenario_test.sh -u 100 -p 1KB [OPTIONS]
```

**Option B — Interactive multi-scenario (full matrix):**

Runs the full `-u`/`-p` matrix. Each scenario gets its own warmup (120s) + 30s cooldown before the main test. Between scenarios the script pauses and prompts for a service restart so the service can be reset.

```bash
./scripts/interactive_test.sh [OPTIONS]
```

**Run in background mode (survives SSH disconnection):**

```bash
./scripts/interactive_test.sh --background [OPTIONS]
```

**Resume a background run after SSH reconnection:**

```bash
./scripts/interactive_test.sh --resume
```

**Monitor background progress:**

```bash
./scripts/check_background_progress.sh --follow
```

## Script Parameters — single_scenario_test.sh

| Flag | Default | Description |
| ------ | --------- | ------------- |
| `-u, --users` | (required) | Concurrent user count for this run |
| `-p, --payload` | (required) | Payload size for this run (e.g. `1KB`) |
| `-d, --duration` | 600 | Test duration in seconds |
| `--warmup-duration` | 120 | Warmup duration in seconds |
| `-n, --dry-run` | false | Preview test order without executing |
| `-h, --help` | — | Show usage |

## Script Parameters — interactive_test.sh

| Flag | Default | Description |
| ------ | --------- | ------------- |
| `-u, --users` | 100,200,500,1000 | Comma-separated concurrent user counts |
| `-p, --payloads` | 1KB,10KB,50KB,100KB,1MB | Comma-separated payload sizes |
| `-d, --duration` | 600 | Test duration per run in seconds |
| `--warmup-duration` | 120 | Warmup duration per scenario in seconds |
| `-b, --background` | false | Run with nohup (survives SSH disconnect) |
| `--resume` | false | Resume a background run after reconnection |
| `-n, --dry-run` | false | Preview test order without executing |
| `-h, --help` | — | Show usage |

## Output

Results are written to timestamped directories inside `scripts/`:

```tree
scripts/
├── logs/<timestamp>/          JMeter log files per test run
└── results/<timestamp>/       JTL files and HTML dashboard reports
```

## References

- Full test methodology: [Performance Testing Proposal - Passthrough](../../docs/performance-testing/passthrough/Proposal.md)
- Analyzed results: [Performance Testing Report - Passthrough](../../reports/performance-testing/passthrough/Report.md)
- Shared assets: [Passthrough Scenario](../../../scenarios/passthrough/README.md)
