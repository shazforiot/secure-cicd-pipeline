# Secure CI/CD Pipeline — Demo Project

> From the video: **"CI/CD Pipeline Security Best Practices 2026"**

This repository contains a fully working, production-ready GitHub Actions workflow that implements all 10 CI/CD security best practices from the tutorial.

---

## What's Included

| File | Description |
|------|-------------|
| `.github/workflows/secure-pipeline.yml` | Complete secure GitHub Actions pipeline |
| `Dockerfile` | Multi-stage, distroless, non-root container |
| `.pre-commit-config.yaml` | Pre-commit hooks for secrets detection |

---

## Prerequisites

- GitHub repository with Actions enabled
- AWS account (for ECR and ECS)
- The following GitHub Secrets configured:
  - `AWS_ACCOUNT_ID` — Your AWS account ID
  - `ECR_REGISTRY` — Your ECR registry URL

---

## Setup Guide

### Step 1: Configure AWS OIDC (Practice #2)

Create an IAM OIDC provider and role for GitHub Actions:

```bash
# 1. Create the OIDC provider (one-time per AWS account)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# 2. Create the trust policy (save as trust-policy.json):
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
EOF

# 3. Create the IAM role
aws iam create-role \
  --role-name GitHubActionsRole \
  --assume-role-policy-document file://trust-policy.json

# 4. Attach the necessary policies
aws iam attach-role-policy \
  --role-name GitHubActionsRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
```

### Step 2: Set Up Branch Protection (Practice #9)

In your GitHub repository:
1. Go to **Settings → Branches**
2. Add a branch protection rule for `main`:
   - ✅ Require a pull request before merging
   - ✅ Require 2 approvals
   - ✅ Dismiss stale pull request approvals
   - ✅ Require review from Code Owners
   - ✅ Require status checks to pass:
     - `secrets-scan / 🔍 Secrets Detection`
     - `sast / 🔬 SAST — CodeQL + Semgrep`
     - `dependency-scan / 📦 Dependency Scan + SBOM`
   - ✅ Require signed commits
   - ✅ Include administrators
   - ✅ Restrict who can push to matching branches

### Step 3: Configure GitHub Environments (Practice #9)

1. Go to **Settings → Environments**
2. Create `staging` environment
3. Create `production` environment — add **Required reviewers**

### Step 4: Install Pre-commit Hooks (Practice #1)

```bash
# Install pre-commit
pip install pre-commit

# Initialize detect-secrets baseline (run from repo root)
pip install detect-secrets
detect-secrets scan > .secrets.baseline

# Install hooks
pre-commit install
pre-commit install --hook-type commit-msg

# Test it works
pre-commit run --all-files
```

### Step 5: Configure Dependabot (Practice #4)

Create `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
    commit-message:
      prefix: "ci(deps)"

  - package-ecosystem: "pip"
    directory: "/"
    schedule:
      interval: "daily"
    open-pull-requests-limit: 10
    commit-message:
      prefix: "chore(deps)"
```

---

## Verifying the Security Controls

### Verify container signature locally

```bash
# Install cosign
brew install cosign  # macOS
# or
curl -O https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
chmod +x cosign-linux-amd64

# Verify an image signature
cosign verify \
  --certificate-identity-regexp="https://github.com/YOUR_ORG/YOUR_REPO/.*" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  YOUR_ECR_REGISTRY/myapp@sha256:YOUR_DIGEST
```

### View SBOM attached to image

```bash
cosign download attestation YOUR_ECR_REGISTRY/myapp@sha256:YOUR_DIGEST \
  | jq -r '.payload' | base64 -d | jq '.predicate'
```

### Run Trivy scan locally

```bash
# Install trivy
brew install trivy  # macOS

# Scan filesystem
trivy fs . --severity CRITICAL,HIGH --exit-code 1

# Scan container image
trivy image YOUR_ECR_REGISTRY/myapp:latest --severity CRITICAL,HIGH
```

---

## Security Best Practices Summary

| Practice | Implementation | File |
|----------|---------------|------|
| #1 Secrets Management | TruffleHog scan + pre-commit | `secure-pipeline.yml` |
| #2 OIDC Auth | `aws-actions/configure-aws-credentials` with OIDC | `secure-pipeline.yml` |
| #3 Dependency Security | Trivy FS scan + Syft SBOM | `secure-pipeline.yml` |
| #4 Action Pinning | All actions pinned to SHA | `secure-pipeline.yml` |
| #5 Container Security | Distroless + Trivy image scan | `Dockerfile`, `secure-pipeline.yml` |
| #6 Artifact Signing | Cosign keyless sign + verify | `secure-pipeline.yml` |
| #7 SAST/DAST | CodeQL + Semgrep + ZAP | `secure-pipeline.yml` |
| #8 Least Privilege | Job-level permissions, `permissions: {}` default | `secure-pipeline.yml` |
| #9 Branch Protection | Required reviews + environments | GitHub Settings |
| #10 Audit Logging | GitHub audit log → SIEM | Configure separately |

---

## Resources

- [Sigstore/Cosign Documentation](https://docs.sigstore.dev)
- [SLSA Framework](https://slsa.dev)
- [Trivy Documentation](https://aquasecurity.github.io/trivy)
- [GitHub OIDC Documentation](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [OpenSSF Scorecard](https://github.com/ossf/scorecard)
