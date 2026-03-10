# Capacity Planning — WSO2 Integration Platform PDP

## Table of Contents

- [Goal](#goal)
- [Why This Matters](#why-this-matters)
- [Customer Tier Model](#customer-tier-model)
- [Test Matrix](#test-matrix)
- [Auto-Scaling Configuration](#auto-scaling-configuration)
- [Success Criteria](#success-criteria)
- [Deliverables](#deliverables)
- [Available Scenarios](#available-scenarios)

## Goal

Determine the **minimum number of replicas** needed to sustain a target RPS under a given CPU/memory configuration. Results feed the customer-facing cost calculator and capacity planning matrix.

## Why This Matters

Customers deploying on WSO2 Integration Platform PDP need to know how many replicas to provision for their expected load. Under-provisioning causes latency degradation; over-provisioning wastes cost. These tests answer: *"for this customer tier, how many replicas are required?"*

## Customer Tier Model

| Tier | Profile | Target RPS | Payload Range |
| ------ | --------- | ------------ | --------------- |
| 1 | Small | 10–50 | 1–10 KB |
| 2 | Medium | 50–200 | 10–50 KB |
| 3 | Large | 200–500 | 10–100 KB |
| 4 | Enterprise | 500–1000 | 10–100 KB |
| 5 | Peak Burst | 1000–2000 | 10–50 KB |

## Test Matrix

Each scenario sweeps across the following dimensions:

- **Target RPS**: derived from the tier table above
- **CPU/memory configs**: e.g., 0.1 vCPU/512 MB, 0.5 vCPU/1 GB, 1.0 vCPU/1 GB
- **Payload sizes**: 1 KB, 10 KB, 50 KB, 100 KB, 250 KB, 1 MB
- **Concurrent connections**: 10, 50, 100, 500

## Auto-Scaling Configuration

Tests use **KEDA/HPA** with scale-to-zero **disabled** for consistent measurements. The minimum replica count is incremented until the success criteria are met.

## Success Criteria

| Metric | Threshold |
| -------- | ----------- |
| Achieved RPS | ≥ 95% of target |
| Error rate | < 1% |
| P95 latency | < 500 ms |

## Deliverables

- Capacity planning matrix (replicas required per tier × CPU/memory config)
- Data for the customer cost calculator
- Customer sizing guide

## Available Scenarios

| Scenario | Description | Status |
| ---------- | ------------- | -------- |
| [passthrough](passthrough/) | HTTP forward with no transformation | Complete |
| [transformation](transformation/) | JSON→XML transformation with backend forward | Pending |
