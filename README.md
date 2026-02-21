# Counter Service - AWS EKS GitOps (FinOps Friendly)

This repository contains a minimal microservice stack:

- Flask backend with PostgreSQL atomic counter, Prometheus metrics, and OpenTelemetry traces.
- Nginx frontend UI that proxies `/api/*` to backend in-cluster service.
- Kubernetes manifests with Kustomize (`manifests/base` + `manifests/overlays/prod`).
- Terraform for EKS, ECR, RDS single-AZ, GitHub OIDC role, CloudFront, and ADOT IRSA role.
- GitHub Actions CI + release pipelines (build/push images and GitOps manifest tag update only).
- Observability values for kube-prometheus-stack and a starter Grafana dashboard JSON.

## Key FinOps choices

- RDS Single-AZ (`multi_az = false`) and small instance class.
- RDS backups toggle: `enable_rds_backups ? 1 : 0`.
- EKS tiny nodegroup (`t3.small`, desired size 1).
- Prometheus retention set to 24h.
- Exactly one public Kubernetes LoadBalancer Service (`frontend`).

## Layout

- `app/` backend service
- `frontend/` static UI + nginx reverse proxy
- `manifests/` Kubernetes + ArgoCD + observability values
- `terraform/` AWS infrastructure
- `dashboards/` Grafana dashboard
- `.github/workflows/` CI and release workflows
