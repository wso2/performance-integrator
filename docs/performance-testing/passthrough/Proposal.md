# Performance Testing Proposal — WSO2 Cloud PDP Passthrough (WSO2 BI)

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

This document describes the methodology for measuring the **maximum achievable throughput** of a WSO2 Ballerina Integration (BI) passthrough service deployed as a single replica on the WSO2 Cloud Private Data Plane (PDP). Results establish per-replica performance ceilings across a range of CPU/memory configurations and provide baseline data for the capacity planning model.

## Objectives

1. Measure the maximum sustained RPS a single replica can handle at each CPU/memory configuration
2. Characterize how throughput scales with vCPU allocation
3. Identify the saturation point (concurrency level at which throughput plateaus or degrades)
4. Provide baseline per-replica throughput data to feed the capacity planning matrix

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
| Server | Netty HTTP echo service v0.4.6-SNAPSHOT |
| Port | 8688 |
| Instance type | t2.large or larger |
| Endpoint | `http://<BACKEND_IP>:8688/service/EchoService` |
| Behavior | Returns request body verbatim |

The backend instance must be in the **same VPC** as the PDP to minimise network overhead.

### WSO2 Cloud PDP Configuration

| Parameter | Value |
| ----------- | ------- |
| Service | Ballerina HTTP passthrough (`bi-svc`) |
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
| S-512 | 0.1 | 512 MB |
| S-1G | 0.1 | 1 GB |
| M-1G | 0.5 | 1 GB |
| L-1G | 1.0 | 1 GB |

### Payload Sizes

| Payload | File |
| --------- | ------ |
| 500 B | `500B.txt` |
| 10 KB | `10KB.txt` |
| 1 MB | `1MB.txt` |

### Concurrent Users

- 100 users
- 1000 users

### Replica Configuration

- **Min replicas**: 1
- **Max replicas**: 1
- **Scale-to-zero**: disabled

## Test Methodology

### Warmup Phase

Before each test run:

| Parameter | Value |
| ----------- | ------- |
| Duration | 5 minutes (300 s) |
| Users | 10 |
| Payload | 500 B |
| Purpose | JVM warm-up, connection pool establishment, cache priming |

### Load Test Phase

| Parameter | Value |
| ----------- | ------- |
| Duration | 10 minutes (600 s) |
| Users | Per configuration (100 or 1000) |
| Payload | Per configuration |
| Ramp-up | 30 s |

Metrics are collected over the stable-state window (after ramp-up completes).

### Cooldown Between Runs

- 2 minutes (120 s) between runs to allow the replica to drain connections and GC

### JMeter JVM Tuning

```bash
export JVM_ARGS="-Xms4g -Xmx8g -XX:MaxMetaspaceSize=512m -Xss256k -XX:+UseG1GC -XX:+UseStringDeduplication -XX:G1HeapRegionSize=16m"
```

## Success Criteria

| Metric | Threshold |
| ----------- | ----------- |
| Error rate | < 1% |
| Throughput | Record achieved RPS at stable state |
| CPU utilisation | Record % at peak load |
| Memory utilisation | Record % at peak load |

There is no minimum RPS threshold — the goal is to record the ceiling, not pass/fail against a target.

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

## Deliverables

1. **Single-replica performance matrix** — throughput and latency for each CPU/memory config × payload × concurrency combination
2. **Saturation curves** — throughput vs. concurrent users for each CPU/memory config, showing the point of diminishing returns
3. **vCPU scaling impact analysis** — comparison of throughput gains when moving from 0.1 → 0.5 → 1.0 vCPU
4. **Baseline data for capacity planning model** — per-replica max RPS values keyed by CPU/memory config and payload size
