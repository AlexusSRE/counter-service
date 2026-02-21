# eks:CreateCluster is denied by the SCP in this OU. The cluster is created once
# via the AWS console and referenced here as a data source. eks:CreateNodegroup
# is allowed, so Terraform fully manages the node group and everything else.

data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "platform" {
  name = var.cluster_name
}

data "aws_vpc" "platform" {
  id = data.aws_eks_cluster.platform.vpc_config[0].vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.platform.id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }
}

locals {
  oidc_issuer = data.aws_eks_cluster.platform.identity[0].oidc[0].issuer
}

data "tls_certificate" "eks" {
  url = local.oidc_issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = local.oidc_issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  tags            = var.tags
}

# ── Networking ────────────────────────────────────────────────────────────────
# The console-created cluster only has private subnets with no internet route.
# Nodes need outbound internet to pull ECR images and reach AWS APIs.
# We add: IGW (imported from existing) + public subnets + NAT + route tables.

resource "aws_internet_gateway" "this" {
  vpc_id = data.aws_vpc.platform.id
  tags   = var.tags
}

resource "aws_subnet" "public" {
  for_each = {
    "eu-west-2a" = "10.0.201.0/24"
    "eu-west-2b" = "10.0.202.0/24"
  }

  vpc_id                  = data.aws_vpc.platform.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true
  tags = merge(var.tags, {
    Name                                 = "${var.project_name}-public-${each.key}"
    "kubernetes.io/role/elb"             = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_route_table" "public" {
  vpc_id = data.aws_vpc.platform.id
  tags   = var.tags

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]
  tags       = var.tags
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["eu-west-2a"].id
  tags          = var.tags
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  vpc_id = data.aws_vpc.platform.id
  tags   = var.tags

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }
}

resource "aws_route_table_association" "private" {
  for_each       = toset(data.aws_subnets.private.ids)
  subnet_id      = each.value
  route_table_id = aws_route_table.private.id
}

# ── EKS Addons ────────────────────────────────────────────────────────────────
# vpc-cni and kube-proxy can install before nodes are ready.
# coredns, ebs-csi, metrics-server, and node-monitoring-agent schedule pods
# and must wait for the node group.

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = data.aws_eks_cluster.platform.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = data.aws_eks_cluster.platform.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = data.aws_eks_cluster.platform.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
  depends_on                  = [aws_eks_node_group.default]
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name                = data.aws_eks_cluster.platform.name
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
  depends_on                  = [aws_eks_node_group.default]
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = data.aws_eks_cluster.platform.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
}

resource "aws_eks_addon" "node_monitoring_agent" {
  cluster_name                = data.aws_eks_cluster.platform.name
  addon_name                  = "eks-node-monitoring-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
  depends_on                  = [aws_eks_node_group.default]
}

# Ships container logs to CloudWatch Logs via Fluent Bit (logs)
# and sends Container Insights metrics to CloudWatch (metrics).
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = data.aws_eks_cluster.platform.name
  addon_name                  = "amazon-cloudwatch-observability"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
  depends_on                  = [aws_eks_node_group.default, aws_iam_role_policy_attachment.node_cloudwatch]
}

# ── EKS Node Group ────────────────────────────────────────────────────────────

resource "aws_iam_role" "node_group" {
  name = "${var.project_name}-node-group-role"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_cloudwatch" {
  role       = aws_iam_role.node_group.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Modern replacement for aws-auth ConfigMap — grants cluster access via EKS API.
resource "aws_eks_access_entry" "node_group" {
  cluster_name  = data.aws_eks_cluster.platform.name
  principal_arn = aws_iam_role.node_group.arn
  type          = "EC2_LINUX"
}

# Grant the Terraform CI role (used by GitHub Actions for kubectl/helm) full
# cluster admin access. The role has AWS AdministratorAccess but EKS has its
# own access control layer that must be configured separately.
resource "aws_eks_access_entry" "terraform_ci" {
  cluster_name  = data.aws_eks_cluster.platform.name
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project_name}-terraform-ci"
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "terraform_ci_admin" {
  cluster_name  = data.aws_eks_cluster.platform.name
  principal_arn = aws_eks_access_entry.terraform_ci.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = data.aws_eks_cluster.platform.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node_group.arn

  subnet_ids = data.aws_subnets.private.ids

  ami_type       = "AL2023_ARM_64_STANDARD"
  instance_types = ["t4g.large"]
  capacity_type  = "ON_DEMAND"

  scaling_config {
    min_size     = 1
    max_size     = 5
    desired_size = 1
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(var.tags, {
    "k8s.io/cluster-autoscaler/enabled"               = "true"
    "k8s.io/cluster-autoscaler/${var.cluster_name}"   = "owned"
  })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
    aws_route_table_association.private,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# ── ECR ──────────────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "backend" {
  name                 = "counter-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
  tags = var.tags
}

resource "aws_ecr_repository" "frontend" {
  name                 = "counter-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration { scan_on_push = true }
  tags = var.tags
}

# ── RDS ──────────────────────────────────────────────────────────────────────

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow PostgreSQL from within the platform VPC"
  vpc_id      = data.aws_vpc.platform.id
  tags        = var.tags
}

resource "aws_security_group_rule" "rds_from_vpc" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = aws_security_group.rds.id
  cidr_blocks       = [data.aws_vpc.platform.cidr_block]
}

resource "aws_security_group_rule" "rds_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = data.aws_subnets.private.ids
  tags       = var.tags
}

resource "aws_db_instance" "postgres" {
  identifier             = "${var.project_name}-postgres"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  storage_type           = "gp3"
  max_allocated_storage  = 30
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  storage_encrypted      = true
  backup_retention_period = var.enable_rds_backups ? 1 : 0
  skip_final_snapshot    = true
  deletion_protection    = false
  multi_az               = false
  tags                   = var.tags
}
