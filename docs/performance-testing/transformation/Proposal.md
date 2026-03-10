# Performance Testing Proposal — WSO2 Integration Platform PDP JSON→XML Transformation (WSO2 BI)

## Table of Contents

- [Introduction](#introduction)
- [Objectives](#objectives)
- [Test Environment](#test-environment)
- [Test Parameters](#test-parameters)
- [Test Methodology](#test-methodology)
- [Success Criteria](#success-criteria)
- [Metrics to Capture](#metrics-to-capture)
- [Deliverables](#deliverables)

## Introduction

This document describes the methodology for measuring the **maximum achievable throughput** of a WSO2 Ballerina Integration (BI) JSON→XML transformation service deployed as a single replica on the WSO2 Integration Platform Private Data Plane (PDP). The service receives a JSON request body containing a `payload` field, converts the inner JSON to XML using `xmldata:fromJson`, and forwards the result to a Netty echo backend.

Results establish per-replica performance ceilings across a range of CPU/memory configurations and provide baseline data for the transformation capacity planning model.

## Objectives

1. Measure the maximum sustained RPS a single replica can handle for the JSON→XML transformation workload at each CPU/memory configuration.
2. Characterize how throughput scales with vCPU allocation when transformation overhead is present.
3. Quantify the throughput reduction relative to the passthrough baseline to isolate the cost of JSON→XML conversion.
4. Identify the saturation point (concurrency level at which throughput plateaus or degrades).
5. Provide baseline per-replica throughput data to feed the transformation capacity planning matrix.

## Test Environment

### Load Generator — JMeter on EC2

| Parameter | Value |
| ----------- | ------- |
| JMeter version | 5.6.3 |
| Instance type | c5.2xlarge (recommended) or equivalent |
| Java version | 21 |
| JVM heap | `-Xms4g -Xmx8g` |
| GC | G1GC (`-XX:+UseG1GC`) |
| Metaspace | `-XX:MaxMetaspaceSize=512m` |
| Stack size | `-Xss256k` |

### Backend — Netty HTTP Echo Server on EC2

| Parameter | Value |
| ----------- | ------- |
| Server | Netty HTTP echo service |
| Port | 8688 |
| Instance type | c5.large or larger (non-burstable, fixed-performance) |
| Endpoint | `http://<BACKEND_IP>:8688/service/EchoService` |
| Behavior | Returns request body verbatim |

The backend instance must be in the **same VPC** as the PDP to minimise network overhead.

### WSO2 Integration Platform PDP Configuration

| Parameter | Value |
| ----------- | ------- |
| Service | Ballerina HTTP JSON→XML transformation (`bi-svc`) |
| Service path | `/jsonToXml` |
| Min replicas | 1 |
| Max replicas | 1 |
| Scale-to-zero | Disabled |
| Config variable | `nettyUrl` — full URL of the Netty echo endpoint |

Auto-scaling is intentionally disabled so all load is absorbed by a single replica.

## Test Parameters

### CPU/Memory Configurations

Each configuration is tested independently with full parameter sweeps:

| Config | vCPU | Memory |
| ----------- | ------ | -------- |
| S-256 | 0.1 | 256 MB |
| S-512 | 0.1 | 512 MB |
| M-512 | 0.5 | 512 MB |
| M-1G | 0.5 | 1 GB |
| L-1G | 1.0 | 1 GB |
| L-2G | 1.0 | 2 GB |

### Payload Sizes

| Payload | File |
| --------- | ------ |
| 1 KB | `1KB.json` |
| 10 KB | `10KB.json` |
| 50 KB | `50KB.json` |
| 100 KB | `100KB.json` |

> Note: 250KB and 1MB sizes are excluded from the transformation scenario. Multi-hundred-KB JSON→XML transformation is CPU-intensive and atypical of production API integration workloads.

### Concurrent Users

- 100 users
- 200 users
- 500 users
- 1000 users

### Replica Configuration

- **Min replicas**: 1
- **Max replicas**: 1
- **Scale-to-zero**: disabled

## Test Methodology

### Warmup Phase

Each scenario (combination of users and payload) gets its own dedicated warmup before the main test run. The service is restarted between scenarios to ensure a clean JVM state.

| Parameter | Value |
| ----------- | ------- |
| Duration | 2 minutes (120 s) |
| Users | 10% of test users, minimum 10 |
| Payload | Same as the main test |
| Purpose | JVM warm-up, connection pool establishment, cache priming |
| Cooldown after warmup | 30 s before the main test starts |

### Load Test Phase

| Parameter | Value |
| ----------- | ------- |
| Duration | 10 minutes (600 s) |
| Users | Per configuration (100, 200, 500, or 1000) |
| Payload | Per configuration |
| Ramp-up | 30 s |

Metrics are collected over the stable-state window (after ramp-up completes).

### Service Restart Between Scenarios

The service is restarted between scenarios (each unique combination of users and payload) to ensure a clean JVM state for each measurement. This replaces the previous fixed cooldown between runs.

### JMeter JVM Tuning

```bash
export JVM_ARGS="-Xms4g -Xmx8g -XX:MaxMetaspaceSize=512m -Xss256k -XX:+UseG1GC -XX:+UseStringDeduplication -XX:G1HeapRegionSize=16m"
```

## Success Criteria

| Metric | Threshold |
| ----------- | ----------- |
| Error rate | < 1% |
| Backend error rate | < 1% — run invalid if exceeded |
| Throughput | Record achieved RPS at stable state |
| CPU utilisation (replica) | Record % at peak load |
| Memory utilisation (replica) | Record % at peak load |
| JMeter CPU | < 80% — run invalid if exceeded |
| JMeter network | < 75% of NIC capacity — run invalid if exceeded |
| Backend CPU headroom | > 20% idle — run invalid if exceeded |
| Backend network | < 75% of NIC capacity — run invalid if exceeded |

There is no minimum RPS threshold — the goal is to record the ceiling, not pass/fail against a target.

If any auxiliary host threshold (JMeter or backend) is exceeded the measured `throughput_rps` is considered invalid and the run must be repeated with a less loaded or larger auxiliary host.

## Metrics to Capture

Each test run produces one row in the results matrix:

| Column | Description |
| ----------- | ------------- |
| `config` | CPU/memory configuration (e.g., M-1G) |
| `payload_size` | Request payload size (e.g., 10KB) |
| `users` | Concurrent user count |
| `throughput_rps` | Achieved requests per second (stable state) |
| `avg_latency_ms` | Mean response time in milliseconds |
| `p95_latency_ms` | 95th percentile response time |
| `p99_latency_ms` | 99th percentile response time |
| `error_pct` | Error rate as a percentage |
| `cpu_pct` | Peak CPU utilisation of the replica |
| `mem_pct` | Peak memory utilisation of the replica |
| `backend_cpu_pct` | Peak CPU utilisation of the backend host |
| `backend_mem_pct` | Peak memory utilisation of the backend host |
| `backend_net_mbps` | Peak network throughput of the backend host (Mbps) |
| `loadgen_cpu_pct` | Peak CPU utilisation of the JMeter host |
| `loadgen_net_mbps` | Peak network throughput of the JMeter host (Mbps) |

## Deliverables

1. **Single-replica performance matrix** — throughput and latency for each CPU/memory config × payload × concurrency combination.
2. **Transformation overhead analysis** — comparison of achieved RPS vs. passthrough baseline per CPU config and payload size.
3. **Saturation curves** — throughput vs. concurrent users for each CPU/memory config, showing the point of diminishing returns.
4. **vCPU scaling impact analysis** — comparison of throughput gains when moving from 0.1 → 0.5 → 1.0 vCPU under transformation workload.
5. **Baseline data for capacity planning model** — per-replica max RPS values keyed by CPU/memory config and payload size.
