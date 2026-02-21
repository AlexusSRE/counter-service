# Counter Service — Nano Service Assignment

A GitOps-deployed counter microservice running on AWS EKS.

## Architecture

```
Browser → CloudFront (HTTPS) → ALB → Nginx (frontend) → Python/Flask (backend) → RDS PostgreSQL
```

| Layer | Technology |
|---|---|
| Frontend | Nginx (static HTML + reverse proxy) |
| Backend | Python Flask + Gunicorn |
| Database | RDS PostgreSQL (db.t4g.micro, gp3) |
| Container runtime | EKS (t4g.medium Graviton nodes, ARM64) |
| Image registry | ECR (counter-backend, counter-frontend) |
| GitOps | Argo CD |
| HTTPS | CloudFront → ALB (HTTP) |
| IaC | Terraform (split into infra + app layers) |
| CI/CD | GitHub Actions (OIDC, no static keys) |

## SCP Constraint & Design Decision

This AWS account is in the **restricted-workloads** OU which has an SCP that
denies `eks:CreateCluster`.

**Solution:** The EKS cluster (`alex-counter-service`) is created once manually
via the AWS console. Terraform then references it as a `data` source and manages
everything else — including the node group, ECR repos, RDS, IAM roles, ALB
controller, and Cluster Autoscaler.

## Terraform layout

```
terraform/
├── infra/   # ECR, RDS, node group, OIDC data source
└── app/     # GitHub Actions IAM, ALB controller, CloudFront, Cluster Autoscaler
```

## Local development

```bash
cp .env.example .env        # fill in values
docker compose up --build
# Frontend: http://localhost:80
```

## Deploy to AWS

1. Run `scripts/bootstrap.ps1` once to create S3/DynamoDB state backend and IAM robot roles.
2. Add `TF_VAR_DB_PASSWORD` as a GitHub Actions secret.
3. Create the EKS cluster manually in the AWS console (name: `alex-counter-service`, see below).
4. Trigger **Infrastructure Bootstrap** workflow in GitHub Actions → runs everything end-to-end.

### EKS cluster settings (console, one-time)

| Setting | Value |
|---|---|
| Name | `alex-counter-service` |
| Kubernetes version | `1.32` |
| Endpoint access | Public |
| VPC | Any VPC with private subnets |

The node group (`t4g.medium`, `AL2_ARM_64`, min 1 / max 5) is created by Terraform automatically.
