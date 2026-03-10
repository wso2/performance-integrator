# Passthrough Scenario

Shared resources used by both **capacity-planning** and **performance-testing** tests for the passthrough scenario. Changes here affect all test categories.

## Table of Contents

- [Directory Contents](#directory-contents)
- [bi-svc](#bi-svc)
- [backend](#backend)
- [Payload Files](#payload-files)

## Directory Contents

```tree
scenarios/passthrough/
└── bi-svc/      Ballerina HTTP passthrough integration service
```

---

## bi-svc

A Ballerina HTTP service that forwards every inbound request to the Netty backend unchanged. It introduces no transformation or business logic, isolating the pure infrastructure overhead of the WSO2 Integration Platform PDP.

**Build:**

```bash
cd bi-svc
bal build
```

**Deploy to WSO2 Integration Platform:**
Create a WSO2 Integration Platform component pointing at this directory. After deployment, set the following **WSO2 Integration Platform config variable**:

| Variable | Description | Example |
| ---------- | ------------- | --------- |
| `nettyUrl` | Full URL of the Netty echo server | `http://<BACKEND_IP>:8688/service/EchoService` |

Refer to the [WSO2 Integration Platform documentation](https://wso2.com/devant/docs/) for deploying Ballerina services.

---

## backend

The shared Netty HTTP echo server lives at [Backend directory](../../../backend/). Refer to the [Backend documentation](../../../backend/README.md) for build and run instructions.

---

## Payload Files

Pre-generated payload files live in [Payloads directory](../../payloads/passthrough/). Each file contains a single JSON object with a `message` field padded to the target size.

| File | Size |
| ------ | ------ |
| `1KB.txt` | ~1 KB |
| `10KB.txt` | ~10 KB |
| `50KB.txt` | ~50 KB |
| `100KB.txt` | ~100 KB |
| `250KB.txt` | ~250 KB |
| `1MB.txt` | ~1 MB |
