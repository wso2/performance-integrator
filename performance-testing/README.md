# Performance Testing — WSO2 Integration Platform PDP

## Table of Contents

- [Goal](#goal)
- [Key Constraint](#key-constraint)
- [CPU/Memory Configurations Tested](#cpumemory-configurations-tested)
- [Test Parameters](#test-parameters)
- [How Results Feed Capacity Planning](#how-results-feed-capacity-planning)
- [Available Scenarios](#available-scenarios)

## Goal

Determine the **maximum achievable throughput** for a **single replica** at a given CPU/memory configuration. These results establish per-replica throughput ceilings that feed into the capacity planning model.

## Key Constraint

Replicas are fixed at **min = max = 1** with scale-to-zero disabled. Auto-scaling is intentionally disabled so that results represent the single-replica ceiling — not aggregate throughput across a scaled-out deployment.

## CPU/Memory Configurations Tested

| vCPU | Memory |
| ------ | -------- |
| 0.1 | 512 MB |
| 0.1 | 1 GB |
| 0.5 | 1 GB |
| 1.0 | 1 GB |

## Test Parameters

- **Concurrent users**: 100, 200, 500, 1000
- **Payload sizes**: 1 KB, 10 KB, 50 KB, 100 KB, 1 MB (passthrough); 1 KB, 10 KB, 50 KB, 100 KB (transformation)

## How Results Feed Capacity Planning

A single replica's maximum throughput sets the per-replica upper bound. Given that number, the capacity planning model can compute: `replicas_needed = ceil(target_RPS / single_replica_max_RPS)`, adjusted for safety margins and latency constraints.

## Available Scenarios

| Scenario | Description | Status |
| ---------- | ------------- | -------- |
| [passthrough](passthrough/) | HTTP forward with no transformation | Complete |
| [transformation](transformation/) | JSON→XML transformation with backend forward | Pending |
