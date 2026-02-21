# ── One-Time Bootstrap ────────────────────────────────────────────────────────
# Run this ONCE from your local machine.
# It creates:
#   1. S3 bucket + DynamoDB table for Terraform remote state
#   2. GitHub OIDC provider in AWS
#   3. The terraform-ci IAM role (AdministratorAccess)
#   4. The github-actions IAM role (ECR push)
#
# After this, all further infra changes go through GitHub Actions.
# ─────────────────────────────────────────────────────────────────────────────

param(
    [string]$Region      = "eu-west-2",
    [string]$ProjectName = "alex-counter-service",
    [string]$GithubOrg   = "AlexusSRE",
    [string]$GithubRepo  = "counter-service"
)

$StateBucket   = "$ProjectName-tfstate"
$DynamoTable   = "$ProjectName-tfstate-lock"
$TfCiRole      = "$ProjectName-terraform-ci"
$GhActionsRole = "$ProjectName-github-actions-role"

# ── Step 1: State backend ─────────────────────────────────────────────────────
Write-Host "`n=== Step 1: Terraform state backend ===" -ForegroundColor Cyan

aws s3api head-bucket --bucket $StateBucket 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating S3 bucket: $StateBucket"
    aws s3api create-bucket `
        --bucket $StateBucket `
        --region $Region `
        --create-bucket-configuration LocationConstraint=$Region
    aws s3api put-bucket-versioning `
        --bucket $StateBucket `
        --versioning-configuration Status=Enabled
    aws s3api put-bucket-encryption `
        --bucket $StateBucket `
        --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
} else {
    Write-Host "S3 bucket already exists, skipping."
}

aws dynamodb describe-table --table-name $DynamoTable --region $Region 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating DynamoDB table: $DynamoTable"
    aws dynamodb create-table `
        --table-name $DynamoTable `
        --attribute-definitions AttributeName=LockID,AttributeType=S `
        --key-schema AttributeName=LockID,KeyType=HASH `
        --billing-mode PAY_PER_REQUEST `
        --region $Region
} else {
    Write-Host "DynamoDB table already exists, skipping."
}

# ── Step 2: GitHub OIDC provider ─────────────────────────────────────────────
Write-Host "`n=== Step 2: GitHub OIDC provider ===" -ForegroundColor Cyan

$OidcArn = aws iam list-open-id-connect-providers `
    --query "OpenIDConnectProviderList[?ends_with(Arn,'token.actions.githubusercontent.com')].Arn" `
    --output text

if ([string]::IsNullOrEmpty($OidcArn) -or $OidcArn -eq "None") {
    Write-Host "Creating GitHub OIDC provider..."
    $OidcArn = aws iam create-open-id-connect-provider `
        --url https://token.actions.githubusercontent.com `
        --client-id-list sts.amazonaws.com `
        --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 `
        --query OpenIDConnectProviderArn `
        --output text
    Write-Host "Created: $OidcArn"
} else {
    Write-Host "Already exists: $OidcArn"
}

$AccountId = aws sts get-caller-identity --query Account --output text

# ── Step 3: terraform-ci role ─────────────────────────────────────────────────
Write-Host "`n=== Step 3: terraform-ci IAM role ===" -ForegroundColor Cyan

# Write trust policy as a plain JSON file (no ConvertTo-Json to avoid encoding bugs)
$TrustFile = [System.IO.Path]::GetTempFileName() + ".json"
@"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Principal": {
        "Federated": "$OidcArn"
      },
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:$GithubOrg/$GithubRepo`:*"
        }
      }
    }
  ]
}
"@ | Out-File -FilePath $TrustFile -Encoding ascii

aws iam get-role --role-name $TfCiRole 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating role: $TfCiRole"
    aws iam create-role `
        --role-name $TfCiRole `
        --assume-role-policy-document file://$TrustFile
    aws iam attach-role-policy `
        --role-name $TfCiRole `
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
} else {
    Write-Host "Role already exists, updating trust policy..."
    aws iam update-assume-role-policy `
        --role-name $TfCiRole `
        --policy-document file://$TrustFile
}

# ── Step 4: github-actions role ───────────────────────────────────────────────
Write-Host "`n=== Step 4: github-actions IAM role ===" -ForegroundColor Cyan

aws iam get-role --role-name $GhActionsRole 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating role: $GhActionsRole"
    aws iam create-role `
        --role-name $GhActionsRole `
        --assume-role-policy-document file://$TrustFile

    $PolicyFile = [System.IO.Path]::GetTempFileName() + ".json"
    @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:CompleteLayerUpload",
        "ecr:GetDownloadUrlForLayer",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart",
        "eks:DescribeCluster"
      ],
      "Resource": "*"
    }
  ]
}
"@ | Out-File -FilePath $PolicyFile -Encoding ascii

    aws iam put-role-policy `
        --role-name $GhActionsRole `
        --policy-name ecr-push-policy `
        --policy-document file://$PolicyFile

    Remove-Item $PolicyFile
} else {
    Write-Host "Role already exists, skipping."
}

Remove-Item $TrustFile

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host "`n=== Bootstrap complete! ===" -ForegroundColor Green
Write-Host ""
Write-Host "terraform-ci role ARN:"
Write-Host "  arn:aws:iam::${AccountId}:role/${TfCiRole}"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Add TF_VAR_DB_PASSWORD as a GitHub Actions secret"
Write-Host "  2. Trigger 'Infrastructure Bootstrap' workflow from GitHub Actions"
