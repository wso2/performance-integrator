# Capacity Planning — Passthrough Scenario

## Table of Contents

- [Scenario](#scenario)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Test Execution](#test-execution)
- [Script Parameters — interactive_test.sh](#script-parameters--interactive_testsh)
- [Script Parameters — single_scenario_test.sh](#script-parameters--single_scenario_testsh)
- [Output](#output)
- [References](#references)

## Scenario

The **passthrough** scenario sends HTTP requests through the Ballerina integration service to the Netty echo backend without any transformation or business logic. This isolates the pure infrastructure overhead of the WSO2 Integration Platform PDP and provides a baseline for all capacity planning calculations.

## Architecture

```txt
JMeter (EC2) → WSO2 Integration Platform NGINX → API Gateway → KEDA → Ballerina Service (PDP) → Netty Backend (EC2)
```

## Prerequisites

1. Shared assets configured — see [Passthrough Scenario](../../../scenarios/passthrough/README.md)
2. EC2 instances running (Netty backend and JMeter client)
3. `bi-svc` deployed to WSO2 Integration Platform with `nettyUrl` config variable set
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

In the WSO2 Integration Platform console, set the replica CPU/memory limits for the `bi-svc` component and set the `nettyUrl` config variable.

### 3. Set environment variables on the JMeter EC2

```bash
export DOMAIN="<your-wso2-integration-platform-endpoint-hostname>"
export AUTH_HEADER="Bearer <your-token>"
export BACKEND_IP="<netty-ec2-ip>"
```

### 4. Run the full matrix test

```bash
./scripts/interactive_test.sh [OPTIONS]
```

**Run in background mode (survives SSH disconnection):**

```bash
./scripts/interactive_test.sh --background [OPTIONS]
```

**Resume a background run after a service restart:**

```bash
./scripts/interactive_test.sh --resume [OPTIONS]
```

**Monitor background progress:**

```bash
./scripts/check_background_progress.sh --follow
```

### 4a. Run a single scenario

To run a single combination of RPS, threads, and payload (includes per-scenario warmup + cooldown):

```bash
./scripts/single_scenario_test.sh -r <RPS> -t <THREADS> -p <PAYLOAD> [OPTIONS]
```

### 5. (Optional) Validate the backend independently

Before running the full test, verify end-to-end connectivity through the WSO2 Integration Platform service:

```bash
./scripts/test_backend.sh [OPTIONS]
```

## Script Parameters — interactive_test.sh

| Flag | Default | Description |
| ------ | --------- | ------------- |
| `-r, --rps` | 10,50,100,200,500,1000,2000,5000 | Comma-separated target RPS values |
| `-p, --payloads` | 1KB,10KB,50KB,100KB,250KB,1MB | Comma-separated payload sizes |
| `-t, --threads` | 10,50,100,500 | Comma-separated concurrent connection counts |
| `-d, --duration` | 600 | Test duration per scenario in seconds |
| `--warmup-duration` | 120 | Per-scenario warmup duration in seconds |
| `-b, --background` | false | Run with nohup (survives SSH disconnect) |
| `--resume` | false | Resume a paused background run |
| `-n, --dry-run` | false | Preview test order without executing |
| `-h, --help` | — | Show usage |

## Script Parameters — single_scenario_test.sh

| Flag | Default | Description |
| ------ | --------- | ------------- |
| `-r, --rps` | — | Target RPS for this scenario (required) |
| `-p, --payload` | — | Payload size for this scenario (required) |
| `-t, --threads` | — | Concurrent connection count (required) |
| `-d, --duration` | 600 | Test duration in seconds |
| `--warmup-duration` | 120 | Warmup duration in seconds (10% of RPS, min 1) |
| `-n, --dry-run` | false | Preview without executing |
| `-h, --help` | — | Show usage |

## Output

Results are written to timestamped directories inside `scripts/`:

```tree
scripts/
├── logs/<timestamp>/          JMeter log files per test run
└── results/<timestamp>/       JTL files and HTML dashboard reports
```

## References

- Full test methodology: [Capacity Planning Proposal - Passthrough](../../docs/capacity-planning/passthrough/Proposal.md)
- Capacity guide: [Capacity Guide - Passthrough](../../docs/capacity-planning/passthrough/CapacityGuide.md)
- Analyzed results: [Capacity Planning Report - Passthrough](../../reports/capacity-planning/passthrough/Report.md)
- Shared assets: [Passthrough Scenario](../../../scenarios/passthrough/README.md)
