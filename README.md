# WSO2 Integrator Performance

Central repository for performance benchmarking, testing frameworks, results, and capacity planning guidance for WSO2 Integration Platform.

## Table of Contents

- [Repository Structure](#repository-structure)
- [Testing Categories](#testing-categories)
- [Documentation](#documentation)

## Repository Structure

```tree
integrator-performance/
├── backend/                             # Shared Netty HTTP echo server (Maven project)
├── scenarios/                           # Shared integration scenarios (Ballerina service code)
│   ├── passthrough/                     # Ballerina HTTP passthrough integration service
│   │   └── bi-svc/                      # Ballerina service that forwards requests unchanged
│   └── transformation/                  # Ballerina HTTP JSON→XML transformation service
│       └── bi-svc/                      # Ballerina service that converts JSON payload to XML
├── payloads/                            # Pre-generated payload files (scenario-specific)
│   ├── passthrough/                     # Plain-text payloads for passthrough (1KB–1MB)
│   └── transformation/                  # JSON payloads for transformation (1KB–100KB)
├── scripts/                             # Shared shell utilities sourced by all test runners
├── docs/                                # Methodology and proposal documents
│   ├── capacity-planning/
│   │   ├── passthrough/                 # Capacity guide, proposal, images
│   │   └── transformation/             # Proposal
│   └── performance-testing/
│       ├── passthrough/                 # Proposal
│       └── transformation/             # Proposal
├── reports/                             # Analyzed test results and findings
│   ├── capacity-planning/
│   │   ├── passthrough/                 # Report and images
│   │   └── transformation/             # Report
│   └── performance-testing/
│       ├── passthrough/                 # Report and images
│       └── transformation/             # Report
├── capacity-planning/                   # Tests to determine minimum replica counts for target RPS
│   ├── passthrough/                     # Passthrough scenario capacity planning
│   │   └── scripts/                     # JMeter test scripts and runners
│   └── transformation/                  # Transformation scenario capacity planning
│       └── scripts/                     # JMeter test scripts and runners
└── performance-testing/                 # Tests to determine maximum single-replica throughput
    ├── passthrough/                     # Passthrough scenario performance testing
    │   └── scripts/                     # JMeter test scripts and runners
    └── transformation/                  # Transformation scenario performance testing
        └── scripts/                     # JMeter test scripts and runners
```

## Testing Categories

| Category | Goal | Location |
| ---------- | ------ | ---------- |
| [Capacity Planning](capacity-planning/) | Given a target RPS, what is the minimum replica count needed? | `capacity-planning/` |
| [Performance Testing](performance-testing/) | For a single replica, what is the maximum achievable RPS? | `performance-testing/` |

See [scenarios/passthrough/README.md](scenarios/passthrough/README.md) and [scenarios/transformation/README.md](scenarios/transformation/README.md) for details on each integration scenario and shared assets.

## Documentation

| Scenario | Category | Document |
| -------- | -------- | -------- |
| Passthrough | Capacity Planning | [Proposal](docs/capacity-planning/passthrough/Proposal.md) · [Guide](docs/capacity-planning/passthrough/CapacityGuide.md) · [Report](reports/capacity-planning/passthrough/Report.md) |
| Passthrough | Performance Testing | [Proposal](docs/performance-testing/passthrough/Proposal.md) · [Report](reports/performance-testing/passthrough/Report.md) |
| Transformation | Capacity Planning | [Proposal](docs/capacity-planning/transformation/Proposal.md) · [Report](reports/capacity-planning/transformation/Report.md) |
| Transformation | Performance Testing | [Proposal](docs/performance-testing/transformation/Proposal.md) · [Report](reports/performance-testing/transformation/Report.md) |
