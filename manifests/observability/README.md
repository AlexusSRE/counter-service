# Observability Stack

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     counter-backend                      │
│  /metrics (Prometheus) ─────────────────────────────►   │
│  OTLP traces ──────────────────────────────────────►    │
└──────────────┬─────────────────────┬────────────────────┘
               │                     │
               ▼                     ▼
    ┌─────────────────┐    ┌──────────────────┐
    │   Prometheus    │    │  ADOT Collector  │
    │  (monitoring ns)│    │   (prod ns)      │
    └────────┬────────┘    └────────┬─────────┘
             │                      │
             ▼                      ▼
      ┌──────────┐           ┌─────────────┐
      │  Grafana │           │  AWS X-Ray  │
      └──────────┘           └─────────────┘

        Fluent Bit (via amazon-cloudwatch-observability EKS addon)
                              │
                              ▼
                    ┌──────────────────┐
                    │  CloudWatch Logs │
                    │  /aws/containers │
                    │  insights/<name> │
                    └──────────────────┘
```

## Logs — AWS CloudWatch

Deployed via the `amazon-cloudwatch-observability` EKS managed addon.

Fluent Bit ships all pod logs to:
```
CloudWatch → Log groups → /aws/containerinsights/alex-counter-service/application
```

View in AWS Console: **CloudWatch → Logs → Log groups**

## Metrics — Prometheus + Grafana

Deployed via Helm (kube-prometheus-stack) into the `monitoring` namespace.

The backend exposes `GET /metrics` with:
- `http_requests_total` — request count by method/endpoint/status
- `http_request_duration_seconds` — latency histogram
- `counter_value` — current counter state

```bash
# Access Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# Open http://localhost:3000  →  admin / admin
# Dashboard: Counter Service → Counter Backend
```

## Traces — AWS X-Ray (bonus)

The ADOT Collector receives OTLP traces from the backend over HTTP and forwards them to X-Ray.

```
backend → http://adot-collector.prod.svc.cluster.local:4318 → ADOT → X-Ray
```

Enabled via `OTEL_ENABLED: "true"` in the backend ConfigMap.

**Where to see traces:** AWS Console → **X-Ray** → **Traces** (or **Service map**).

- Direct link: https://eu-west-2.console.aws.amazon.com/xray/home?region=eu-west-2#/traces
- Filter by service name: `counter-backend`
- Generate traffic (click the counter in the app), then refresh the Traces list; each request appears as a trace with spans for Flask, SQL, etc.

**Troubleshooting traces**

1. Confirm backend has OTEL env:  
   `kubectl exec -n prod deployment/backend -- env | grep OTEL`  
   Expect `OTEL_ENABLED=true`, `OTEL_EXPORTER_OTLP_ENDPOINT=http://adot-collector.prod.svc.cluster.local:4318`.

2. Check ADOT collector is receiving:  
   `kubectl logs -n prod deployment/adot-collector -f --tail=100`  
   With the `logging` exporter enabled you should see trace/span log lines when the app is used.

3. If ADOT logs show traces but X-Ray does not, check the collector pod’s IAM (IRSA) has `AWSXRayDaemonWriteAccess` and the X-Ray console is set to region `eu-west-2`.
