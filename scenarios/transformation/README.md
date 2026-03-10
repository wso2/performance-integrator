# Transformation Scenario

Shared resources used by both **capacity-planning** and **performance-testing** tests for the JSON-to-XML transformation scenario. Changes here affect all test categories.

## Table of Contents

- [Directory Contents](#directory-contents)
- [bi-svc](#bi-svc)
- [Payload Files](#payload-files)

## Directory Contents

```tree
scenarios/transformation/
└── bi-svc/      Ballerina HTTP JSON→XML transformation integration service
```

---

## bi-svc

A Ballerina HTTP service that accepts a JSON request body with a `payload` field, converts the inner payload to XML using `xmldata:fromJson`, and forwards the resulting XML to the Netty backend.

**Request format:**

```json
{
  "payload": { ...structured JSON object... }
}
```

**Flow:**

```txt
JMeter → WSO2 Integration Platform NGINX → API Gateway → Ballerina bi-svc (PDP) → Netty Echo Backend (EC2)
```

The service extracts `data.payload`, calls `xmldata:fromJson(payload)` to produce XML, then forwards the XML to the Netty backend via HTTP POST to `/service/EchoService`.

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

**Service path:** `/jsonToXml` (POST to `https://<domain>/perf-test-jmeter/bi-transformation/v1.0`)

---

## Payload Files

Pre-generated JSON payload files live in [Payloads directory](../../payloads/transformation/). Each file contains a realistic order JSON object with a structured `payload` field. The inner `payload` is a valid JSON object that `xmldata:fromJson` can convert to XML.

**Payload structure:**

```json
{
  "payload": {
    "orderId": "...",
    "status": "...",
    "currency": "...",
    "totalAmount": 0.00,
    "createdAt": "...",
    "customer": { "id", "firstName", "lastName", "email", "phone" },
    "shippingAddress": { "street", "city", "state", "zipCode", "country" },
    "items": [ { "sku", "name", "quantity", "unitPrice", "subtotal", ... }, ... ]
  }
}
```

| File | Size | Items |
| ------ | ------ | ------- |
| `1KB.json` | ~1 KB | 3 items (basic fields) |
| `10KB.json` | ~10 KB | 12 items (with category, weight, dimensions, supplier, description, tags) |
| `50KB.json` | ~50 KB | 64 items (extended fields) |
| `100KB.json` | ~100 KB | 128 items (extended fields) |

> Note: 250KB and 1MB sizes are excluded. Multi-hundred-KB JSON→XML transformation is an atypical use case; the conversion overhead at those sizes makes the scenario less representative of production API integration workloads.

---

## backend

The shared Netty HTTP echo server lives at [Backend directory](../../../backend/). Refer to the [Backend documentation](../../../backend/README.md) for build and run instructions.
