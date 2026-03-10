# Capacity Planning Proposal — WSO2 Integration Platform PDP JSON→XML Transformation (WSO2 BI)

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

This document describes the methodology for **capacity planning** of a WSO2 Integrator (BI) JSON→XML transformation service deployed on the WSO2 Integration Platform Private Data Plane (PDP). Building on the single-replica performance baselines established in the [Performance Testing Report](../../../reports/performance-testing/transformation/Report.md), this study determines the **minimum number of replicas** required to sustain a set of predefined throughput targets for a workload that includes JSON parsing, XML serialization, and backend forwarding.

Unlike the passthrough scenario, the transformation scenario introduces CPU-bound processing (JSON→XML conversion via `xmldata:fromJson`) on every request. This is expected to reduce the per-replica throughput ceiling and shift the CPU saturation point relative to the passthrough baseline.

## Objectives

1. Determine the **minimum number of replicas** required to sustain each target throughput level for the JSON→XML transformation workload across a range of payload sizes, concurrent user counts, and resource configurations.
2. Quantify the throughput overhead introduced by JSON→XML transformation relative to the passthrough baseline.
3. Expand payload coverage to include 1KB, 10KB, 50KB, and 100KB to capture the spectrum of typical API integration transformation workloads.
4. Broaden concurrency coverage to 10, 50, 100, 200, and 500 concurrent users.
5. Provide a **capacity planning matrix** that maps `(throughput target, payload size, resource configuration, concurrency)` → `minimum replicas`, suitable for production deployment guidance.

## Test Environment

### Load Generator — JMeter on EC2

| Parameter | Value |
| ----------- | ------- |
| JMeter version | 5.6.3 |
| Instance type | `m6a.xlarge` (4 vCPU, 16 GiB RAM, up to 12.5 Gbps network) |
| Java version | 21 |
| JVM heap | `-Xms4g -Xmx8g` |
| GC | G1GC (`-XX:+UseG1GC`) |
| Metaspace | `-XX:MaxMetaspaceSize=512m` |
| Stack size | `-Xss256k` |

### Backend — Netty HTTP Echo Server on EC2

| Parameter | Value |
| ----------- | ------- |
| Server | Netty HTTP echo service |
| Instance type | `c5.xlarge` |
| Behavior | Returns request body verbatim |

The backend instance must be in the **same VPC** as the PDP to minimise network overhead.

### WSO2 Integration Platform PDP Configuration

| Parameter | Value |
| ----------- | ------- |
| Product | WSO2 Integrator: BI (Ballerina 2202.13.1 — Swan Lake Update 13) |
| Service | Ballerina HTTP JSON→XML transformation service (`bi-svc`) |
| Scale-to-zero | Disabled |
| Endpoint authentication | Enabled |
| Min replicas | 1 |
| Max replicas | Varies per test (scaled to meet throughput target) |

Scale-to-zero is disabled to eliminate cold-start variability from measurements.

## Test Parameters

### Resource Configurations

Four configurations are tested, covering minimal to high-performance resource tiers:

| Config | vCPU | Memory |
|--------|------|--------|
| XS     | 0.2  | 512 MB |
| S      | 0.5  | 1 GB   |
| M      | 1.0  | 1 GB   |
| L      | 2.0  | 1 GB   |

### Throughput Targets

Tests target fixed constant throughput levels (stress testing, not open-loop):

- **50 RPS** — baseline / light load
- **100 RPS** — low production load
- **200 RPS** — moderate load
- **500 RPS** — high load
- **1,000 RPS** — very high load
- **2,000 RPS** — extreme load
- **5,000 RPS** — upper boundary exploration

### Payload Sizes

| Payload | File | Representative Scenario |
| --------- | ------ | ------------------------ |
| 1 KB | `1KB.json` | Simple order with 3 line items |
| 10 KB | `10KB.json` | Medium order with 12 line items |
| 50 KB | `50KB.json` | Large order with 64 line items |
| 100 KB | `100KB.json` | Extra-large order with 128 line items |

> 250KB and 1MB sizes are excluded. Multi-hundred-KB JSON→XML transformation is CPU-intensive and atypical of production API integration workloads.

### Concurrent Users

- 10, 50, 100, 200, 500 users

### Test Matrix Constraint

Not all combinations of throughput × concurrency × payload are valid. Network bandwidth and CPU saturation constraints apply. Combinations that would saturate the JMeter client's network interface are excluded from the matrix.

## Test Methodology

### Approach: Stress Testing (Constant Throughput)

This study uses **stress testing** — JMeter targets a constant throughput rate (via `ConstantThroughputTimer`) and the system must sustain it. This directly maps to production SLA targets and isolates replica count as the control variable.

### N/A (Not Achievable) Definition

A result is recorded as **N/A** when the target throughput cannot be achieved regardless of replica count, due to **Little's Law**:

```equation
Average Effective Throughput = Concurrent Users / Average Latency
```

When per-request latency (including transformation overhead) is high enough that the concurrent user count is insufficient to generate the target RPS, no amount of horizontal scaling resolves the constraint.

### Warmup Phase

Each scenario (combination of target RPS, threads, and payload) gets its own dedicated warmup before the main test run. The service is restarted between scenarios to ensure a clean JVM state.

| Parameter | Value |
| ----------- | ------- |
| Duration | 2 minutes (120 s) |
| Warmup RPS | 10% of target RPS, minimum 1 |
| Threads | Same as the main test |
| Payload | Same as the main test |
| Purpose | JVM warm-up, connection pool establishment, cache priming |
| Cooldown after warmup | 30 s before the main test starts |

### Stress Test Phase

| Parameter | Value |
| ----------- | ------- |
| Duration | 10 minutes (600 s) per configuration |
| Target throughput | Per matrix entry (constant RPS) |
| Users | Per matrix entry |
| Payload | Per matrix entry |
| Ramp-up | 30 s |

Metrics are collected over the stable-state window after ramp-up completes.

### Replica Discovery Procedure

For each `(throughput target, payload size, concurrent users, resource configuration)` combination:

1. Start with **1 replica**.
2. Run the stress test at the target RPS for 10 minutes.
3. If throughput is sustained with error rate < 1%, record **minimum replicas = current count**.
4. If throughput cannot be sustained, increment replica count and repeat from step 2.
5. If throughput cannot be achieved at any replica count (due to Little's Law), record **N/A**.

### Service Restart Between Scenarios

The service is restarted between scenarios (each unique combination of target RPS, threads, and payload) to ensure a clean JVM state for each measurement. This replaces the previous fixed cooldown between runs.

### JMeter JVM Tuning

```bash
export JVM_ARGS="-Xms4g -Xmx8g -XX:MaxMetaspaceSize=512m -Xss256k -XX:+UseG1GC -XX:+UseStringDeduplication -XX:G1HeapRegionSize=16m"
```

## Success Criteria

| Metric | Threshold |
| ----------- | ----------- |
| Error rate | < 1% during stable-state window |
| Throughput | Achieved RPS ≥ target RPS (within 5% tolerance) |
| CPU utilisation | Monitored and recorded; not a pass/fail criterion |
| Memory utilisation | Monitored and recorded; not a pass/fail criterion |

## Metrics to Capture

Each test run produces one row in the capacity planning matrix:

| Column | Description |
| ----------- | ------------- |
| `target_rps` | Target throughput (RPS) |
| `concurrent_users` | Concurrent user count |
| `payload_size` | Request payload size |
| `cpu_per_replica` | vCPU allocated per replica |
| `memory_per_replica_mb` | Memory allocated per replica (MB) |
| `min_replicas` | Minimum replicas to sustain target RPS, or N/A |
| `achieved_rps` | Actual stable-state throughput (RPS) |
| `avg_latency_ms` | Mean response time (ms) |
| `p95_latency_ms` | 95th percentile response time (ms) |
| `p99_latency_ms` | 99th percentile response time (ms) |
| `error_pct` | Error rate (%) |
| `max_cpu_pct` | Peak CPU utilisation of a replica (%) |
| `max_mem_pct` | Peak memory utilisation of a replica (%) |

## Deliverables

1. **Capacity planning matrix** — minimum replicas for each `(throughput target × payload size × concurrent users × resource configuration)` combination.
2. **Transformation overhead analysis** — per-payload-size comparison of transformation vs. passthrough replica requirements.
3. **Payload size guidelines** — maximum recommended throughput per payload size with required resource configuration.
4. **Cost-performance analysis** — RPS/CPU and RPS/GB efficiency metrics for each resource configuration.
5. **Little's Law analysis** — documentation of N/A scenarios with root-cause attribution to latency constraints vs. resource limits.
6. **Resource optimisation recommendations** — recommended configuration tiers for different production transformation workload profiles.
