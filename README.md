# Counter Service — Nano Service Assignment

A GitOps-deployed counter microservice running on AWS EKS with full CI/CD, observability, and high-availability.

---

## Architecture

```
Browser
  └── CloudFront (HTTPS, CDN, global edge)
        └── ALB (HTTP/80 — AWS Load Balancer Controller)
              ├── Nginx frontend (static HTML + /api/ reverse proxy)
              └── Python/Flask backend (Gunicorn, port 8080)
                    └── RDS PostgreSQL (db.t4g.micro, gp3, encrypted at rest)
```

| Layer | Technology |
|---|---|
| Frontend | Nginx Alpine — static HTML, proxies `/api/` to backend |
| Backend | Python 3.12 · Flask · Gunicorn |
| Database | RDS PostgreSQL 16 — db.t4g.micro, gp3, storage-encrypted |
| Cluster | EKS 1.32 — t4g.medium Graviton nodes (AL2023 ARM64) |
| Image registry | ECR — `counter-backend`, `counter-frontend` |
| GitOps | Argo CD — auto-sync on manifest changes |
| HTTPS | CloudFront → ALB (HTTP); TLS terminated at CloudFront |
| IaC | Terraform split into `infra` and `app` layers |
| CI/CD | GitHub Actions with OIDC — no static AWS keys |
| Metrics | Prometheus + Grafana (kube-prometheus-stack) |
| Logs | Amazon CloudWatch via Fluent Bit (CW Observability addon) |
| Traces | ADOT Collector → AWS X-Ray (optional, toggle via env var) |

---

## SCP Constraint & Design Decision

This AWS account is in the **restricted-workloads** OU, which has an SCP that denies `eks:CreateCluster`.

**Solution:** The EKS cluster (`alex-counter-service`) is created once manually via the AWS console.
Terraform then references it as a `data` source and manages everything else — node group, networking,
ECR, RDS, IAM roles, ALB controller, Cluster Autoscaler, and CloudFront.

---

## Repository Layout

```
.
├── backend/                       # Flask app, Dockerfile, requirements.txt
├── frontend/                      # Nginx static app, Dockerfile, nginx.conf
├── manifests/
│   ├── base/                      # Kustomize base — Deployments, Services, Ingress, ADOT
│   ├── overlays/prod/             # Production overlay — namespace + pinned image tags
│   ├── argocd/                    # Argo CD Application manifest
│   └── observability/             # kube-prometheus-stack Helm values + README
├── terraform/
│   ├── infra/                     # ECR, RDS, node group, OIDC provider, networking
│   └── app/                       # GitHub OIDC, IAM roles, ALB controller, Cluster Autoscaler, CloudFront
├── scripts/
│   └── bootstrap.ps1              # One-time: S3/DynamoDB state backend + IAM robot roles
└── dashboards/
    └── counter-dashboard.json     # Grafana dashboard — request rate, latency, counter value
```

---

## 1. Provisioning the Cluster

### Prerequisites

- AWS CLI configured with admin-level credentials in `eu-west-2`
- Terraform ≥ 1.8
- PowerShell 7+ (for the bootstrap script)
- GitHub repository secrets configured (see [Credentials](#2-credentials-and-secrets))

### Step 1 — Bootstrap state backend and robot IAM roles (one-time)

```powershell
./scripts/bootstrap.ps1
```

Creates:
- S3 bucket + DynamoDB table for Terraform remote state
- `alex-counter-service-terraform-ci` — IAM role assumed by GitHub Actions (via OIDC) to run Terraform
- `alex-counter-service-github-actions-role` — IAM role assumed by GitHub Actions to push images to ECR

### Step 2 — Create the EKS cluster manually (one-time, SCP constraint)

In the AWS console, region **eu-west-2**:

| Setting | Value |
|---|---|
| Name | `alex-counter-service` |
| Kubernetes version | `1.32` |
| Cluster endpoint access | Public |
| Update policy | **STANDARD** (EXTENDED is denied by SCP) |
| VPC | Existing VPC with private subnets |

The node group and all other infrastructure are created automatically by Terraform in the next step.

### Step 3 — Run the full bootstrap pipeline

Trigger **Infrastructure Bootstrap** in GitHub Actions via `workflow_dispatch`.

The pipeline runs five sequential stages:

| Stage | What it does |
|---|---|
| **Terraform Infra** | ECR repos, OIDC provider, NAT gateway, node group, RDS PostgreSQL |
| **Terraform App** | GitHub OIDC, IAM roles, ALB controller (Helm), Cluster Autoscaler (Helm), CloudFront |
| **Install Argo CD** | Deploys Argo CD into the `argocd` namespace |
| **Observability Stack** | Installs kube-prometheus-stack (Prometheus + Grafana) into `monitoring` namespace |
| **Deploy App** | Seeds Kubernetes secrets/ConfigMaps, registers Argo CD Application, triggers initial sync |

---

## 2. Credentials and Secrets

### GitHub Actions secrets required

| Secret | Purpose |
|---|---|
| `TF_VAR_DB_PASSWORD` | RDS master password (≥ 12 chars). Used by Terraform to create the RDS instance and injected as a Kubernetes Secret at deploy time. |
| `ACTIONS_GITHUB_TOKEN` | GitHub PAT with `contents: write`. Allows the release workflow to commit updated Kustomize image tags back to `main`. |

### How secrets reach the running pod

The bootstrap pipeline runs:

```bash
kubectl create secret generic backend-db \
  --namespace=prod \
  --from-literal=DB_PASSWORD=<TF_VAR_DB_PASSWORD>
```

The backend Deployment mounts this Secret as environment variables via `secretRef`.
**The DB password is never stored in Git** — only in GitHub Actions secrets and the live Kubernetes Secret.

### AWS credentials — no static keys

GitHub Actions assumes IAM roles via **OIDC**. There are no `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`
secrets anywhere. The trust policies are scoped to `repo:AlexusSRE/counter-service:*`.

| Role | Used by | Permissions |
|---|---|---|
| `alex-counter-service-terraform-ci` | Bootstrap + Terraform workflows | AdministratorAccess (scoped to this repo) |
| `alex-counter-service-github-actions-role` | Release workflow | ECR push + `eks:DescribeCluster` only |

### Rotating the DB password

1. Update the `TF_VAR_DB_PASSWORD` secret in GitHub Actions settings.
2. Re-run **Infrastructure Bootstrap** — Terraform updates RDS and the pipeline re-creates the Kubernetes Secret.

---

## 3. Running the Pipeline

### CI — pull request validation

**Workflow:** `.github/workflows/ci.yml`

Runs on every pull request:
1. Validates Python syntax with `py_compile`
2. Builds both Docker images for `linux/amd64` (no push) to catch Dockerfile regressions

### Release / CD — push to `main`

**Workflow:** `.github/workflows/release.yml`

Triggered automatically on any push to `main` (skips manifest-only changes):

1. Builds multi-arch images (`linux/amd64` + `linux/arm64`) and pushes to ECR with tag `sha-<GIT_SHA>`
2. Updates `manifests/overlays/prod/kustomization.yaml` with the new image tag
3. Commits the manifest change back to `main`
4. Argo CD detects the change and auto-syncs — no manual `kubectl apply` needed

### Infrastructure changes

**Workflows:** `.github/workflows/terraform-infra.yml` and `.github/workflows/terraform-app.yml`

Run manually (`workflow_dispatch`) or on push to `main` (app layer only).

---

## 4. Deploy and Test

### Deploying a change

Push any code change to `main`:

```bash
git commit -m "feat: update counter page text"
git push origin main
```

The release workflow fires automatically → builds new images → updates Kustomize overlay → Argo CD rolls
out the new pods within ~2 minutes.

### Verifying the service

```bash
# Get the ALB hostname
kubectl get ingress -n prod

# Or use the CloudFront domain from Terraform output:
# terraform -chdir=terraform/app output cloudfront_domain

# Increment the counter
curl -X POST https://<url>/api/counter    # {"value": 1}

# Read the counter
curl         https://<url>/api/counter    # {"value": 1}

# Health check (used by liveness + readiness probes)
curl         https://<url>/healthz        # {"status": "ok"}

# Prometheus metrics
curl         https://<url>/metrics
```

### Checking cluster state

```bash
# Configure local kubectl
aws eks update-kubeconfig --region eu-west-2 --name alex-counter-service

kubectl get pods,deployment,svc,ingress,hpa,pdb -n prod
```

### Argo CD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080
# Username: admin
# Password: kubectl -n argocd get secret argocd-initial-admin-secret \
#             -o jsonpath="{.data.password}" | base64 -d
```

### Grafana (metrics)

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# Open: http://localhost:3000  →  admin / admin
# Import: dashboards/counter-dashboard.json
```

### CloudWatch logs

AWS Console → **CloudWatch → Log groups** →
`/aws/containerinsights/alex-counter-service/application`

### X-Ray traces

AWS Console → **X-Ray → Traces** → filter by `service.name = counter-backend`

### Local development

```bash
cp .env.example .env        # fill in DB credentials
docker compose up --build
# Frontend: http://localhost:80
```

---

## 5. HA, Scaling, Persistence — Choices and Trade-offs

### High Availability

| Mechanism | Detail |
|---|---|
| Multi-AZ nodes | Node group spans `eu-west-2a` and `eu-west-2b` (private subnets in both AZs) |
| Cluster Autoscaler | Scales node group 1 → 5; scale-down threshold 50% CPU, 2 min delay after add |
| Pod replicas | Backend and frontend each run ≥ 2 replicas in the prod overlay |
| PodDisruptionBudget | Ensures ≥ 1 pod stays up during node drains and rolling updates |
| Rolling updates | `maxUnavailable: 1` on the node group; Deployments use rolling strategy by default |
| RDS | Single-AZ `db.t4g.micro` — durable, automated daily backups, but no read replica |

**Biggest HA gap:** A single-AZ RDS instance means ~2 min downtime on primary failure.
Enabling `multi_az = true` in `terraform/infra/main.tf` adds a standby replica with automatic failover.

### Auto-scaling

| Mechanism | Scope | Detail |
|---|---|---|
| Cluster Autoscaler | Nodes | Adds/removes EC2 instances based on pending pods and utilisation |
| HPA (CPU-based) | Pods | Scales backend replicas 2 → 10 at 70% CPU target |

**KEDA** would allow request-rate–based or queue-based scaling but adds operational complexity and is not deployed here.

### Persistence

**Chosen approach: RDS PostgreSQL**

The counter lives in a single row (`request_counter_state.value`), incremented atomically with
`UPDATE … RETURNING value` — no race conditions with multiple replicas.

| Approach | Pros | Cons |
|---|---|---|
| **RDS PostgreSQL** (chosen) | Durable, ACID, managed backups, multi-replica safe, survives pod/node restarts | Higher latency than in-memory, has operational cost |
| Redis | Very fast, flexible data structures | Needs AOF/RDB for persistence, another component to operate |
| PVC (SQLite / file) | Zero external dependencies | `ReadWriteOnce` — breaks with > 1 replica; no managed backups |
| In-memory (original) | Zero setup | Counter lost on every pod restart |

All storage is encrypted at rest (`storage_encrypted = true` on RDS; gp3 EBS uses AWS-managed keys by default).

### Security

| Practice | Implementation |
|---|---|
| Non-root container | `USER 1001` in both Dockerfiles |
| Minimal image | Python 3.12-slim (backend), Nginx Alpine (frontend); multi-stage builds |
| No static AWS keys | GitHub Actions uses OIDC; trust policy scoped to this repository |
| Least-privilege IAM | Release role can only push to ECR; Terraform CI role scoped to CI workflows |
| Kubernetes RBAC | Backend ServiceAccount has no extra cluster permissions; ADOT IRSA scoped to `prod:adot-collector` |
| Secrets never in Git | DB password only in GitHub Actions secret + live Kubernetes Secret |
| Image scanning | ECR `scan_on_push = true` on both repositories |

### Observability

| Signal | Tool | Detail |
|---|---|---|
| **Logs** | CloudWatch via Fluent Bit | `amazon-cloudwatch-observability` EKS addon ships all pod logs |
| **Metrics** | Prometheus + Grafana | `/metrics`: `http_requests_total`, `http_request_duration_seconds`, `counter_value` |
| **Traces** | ADOT → X-Ray | OTLP exporter enabled via `OTEL_ENABLED=true` in backend ConfigMap |

See [`manifests/observability/README.md`](manifests/observability/README.md) for architecture diagram and access commands.

### Rollback Strategy

Every image push updates `manifests/overlays/prod/kustomization.yaml` with a new Git commit.
Rollback is a one-liner:

```bash
# Find the previous commit hash
git log --oneline manifests/overlays/prod/kustomization.yaml

# Revert the manifest commit and push — Argo CD auto-syncs the rollback
git revert <commit-sha>
git push origin main
```

Alternatively, use the **Argo CD UI → History and Rollback** panel to select any previous sync without touching Git.
