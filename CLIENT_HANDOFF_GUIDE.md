# Client Handoff Guide

This is the short source of truth for the Order Platform demo handoff.

## What This Deploys

```text
CloudFront HTTPS -> ALB HTTP -> ECS Fargate Order API -> RDS PostgreSQL
Order API -> SQS -> Lambda -> RDS, DynamoDB, S3 invoices, SES, SNS
Jenkins -> ECR -> ECS and Lambda deploy
```

The AWS region is `us-east-2`. CloudFront uses the default CloudFront certificate; no custom domain, Route53, or ACM certificate is required.

API auth is intentionally disabled for demo usability:

```text
AUTH_ENABLED=false
```

No app API key or OpenAI/GPT key is required.

## Important Files

```text
infra/main.tf                  # Root Terraform wiring
infra/variables.tf             # Root inputs
infra/outputs.tf               # Terraform outputs
infra/terraform.tfvars         # Local demo values
infra/environments/dev.tfvars  # Jenkins infra pipeline values
infra/modules/                 # Terraform modules
services/order-api/            # Node.js API and built-in UI
services/order-processor/      # Lambda source of truth
scripts/package-lambda.sh      # Syncs Lambda source/deps into Terraform package dir
jenkins/Jenkinsfile            # App + Lambda deployment pipeline
jenkins/Jenkinsfile.infra      # Optional Terraform pipeline
```

## Values To Review

Before deployment, check these values:

```text
infra/terraform.tfvars
infra/environments/dev.tfvars
```

Required values:

```hcl
admin_cidr      = "CLIENT_PUBLIC_IP/32"
key_pair_name   = "CLIENT_EXISTING_EC2_KEY_PAIR"
repo_url        = "https://github.com/client-org/order-platform.git"
ses_from_email  = "verified-sender@example.com"
```

Optional safety values:

```hcl
rds_skip_final_snapshot = true
rds_deletion_protection = false
```

For a real production database, set deletion protection and final snapshot behavior more conservatively.

## Terraform State

`infra/versions.tf` does not hardcode an S3 backend. That is intentional.

For local deployment, create or choose a state bucket and generate `infra/backend.generated.tf`:

```bash
cd infra
cat > backend.generated.tf <<'EOF'
terraform {
  backend "s3" {}
}
EOF

terraform init -reconfigure \
  -backend-config="bucket=order-platform-tfstate-<aws-account-id>" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=us-east-2"
```

For Jenkins infra deployment, use `jenkins/Jenkinsfile.infra`. It computes the active AWS account ID, creates/checks bucket `order-platform-tfstate-<account-id>`, writes `backend.generated.tf`, and runs Terraform against `infra/environments/dev.tfvars`.

## Local Checks

Run these before applying:

```bash
python -m pytest services/order-processor/tests
bash scripts/package-lambda.sh

terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra init -backend=false
terraform -chdir=infra validate
terraform -chdir=infra plan -refresh=false -input=false -var-file=environments/dev.tfvars

cd services/order-api
npm ci
npm test
```

## Deploy Infrastructure

After backend init:

```bash
bash scripts/package-lambda.sh
terraform -chdir=infra plan -input=false -var-file=environments/dev.tfvars
terraform -chdir=infra apply -input=false -var-file=environments/dev.tfvars
```

Save these outputs:

```text
jenkins_public_ip
alb_dns_name
cloudfront_distribution_domain_name
invoice_bucket_name
order_queue_url
lambda_function_name
ecs_cluster_name
ecs_service_name
```

The initial ECS service may be unhealthy until Jenkins builds and pushes the first real image. Terraform points ECS at a bootstrap tag; Jenkins replaces it with an immutable build tag.

## Jenkins Setup

Open Jenkins:

```text
http://<jenkins_public_ip>:8080
```

Unlock it from the Jenkins EC2 instance:

```bash
ssh -i "<key-pair.pem>" ec2-user@<jenkins_public_ip>
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Install suggested plugins and the Workspace Cleanup plugin, because the app pipeline uses `cleanWs()`.

Create a Pipeline job:

```text
Repository URL: https://github.com/client-org/order-platform.git
Branch: */main
Script Path: jenkins/Jenkinsfile
```

The app pipeline:

- runs API tests with `npm ci`
- runs Lambda tests
- packages Lambda from `services/order-processor`
- builds and pushes an immutable ECR image tag
- updates Lambda code
- updates ECS
- fails smoke testing unless `POST /orders` returns `201`

ECR URLs are computed from `aws sts get-caller-identity`; do not hardcode the AWS account ID.

## Database Seed

Terraform seeds the database through AWS Systems Manager on the Jenkins EC2 instance. It no longer needs a local private key path.

If the automatic seed does not run, use SSM Run Command or SSH into Jenkins and run:

```bash
cd ~
rm -rf order-platform
git clone https://github.com/client-org/order-platform.git order-platform
cd order-platform

SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id <db-secret-arn> \
  --region us-east-2 \
  --query SecretString \
  --output text)

DB_USER=$(echo "$SECRET_JSON" | jq -r .username)
DB_PASS=$(echo "$SECRET_JSON" | jq -r .password)

PGPASSWORD="$DB_PASS" psql \
  "host=<rds-host> port=5432 dbname=mydb user=$DB_USER sslmode=require" \
  -f scripts/seed-db.sql
```

Seeded product IDs include `SMOKE-001`, `PROD-001`, `PROD-002`, `PROD-003`, and `PROD-004`.

## Test The App

Use CloudFront for browser testing:

```text
https://<cloudfront_distribution_domain_name>/
```

CloudFront redirects HTTP viewers to HTTPS and uses the ALB as an HTTP origin.

Health:

```bash
curl http://<alb_dns_name>/health
```

Create order:

```bash
curl -i -X POST http://<alb_dns_name>/orders \
  -H "Content-Type: application/json" \
  -d '{"customer_email":"test@example.com","items":[{"product_id":"SMOKE-001","qty":1}]}'
```

Expected success is `201`. Invalid email, empty items, fractional quantity, zero quantity, and negative quantity return `400`. Missing products or insufficient stock return conflict errors. If SQS publish fails after the DB commit, the API marks the order `FAILED`, restores stock, and returns the affected `order_id`.

## Operational Notes

- Lambda invoice keys and payment references are deterministic per order, so SQS retries do not create duplicate invoice objects.
- SES and SNS failures after order completion are best-effort and logged; they do not create retry loops.
- The invoice bucket has public access blocked.
- ECR tags are immutable. Roll back by deploying a previous immutable tag with `jenkins/scripts/rollback.sh <tag>`.
- RDS storage encryption is enabled.
- Demo destroy is easier because ECR and invoice S3 cleanup are enabled.

## Destroy Demo Environment

```bash
terraform -chdir=infra destroy -input=false -var-file=environments/dev.tfvars
```

If `rds_deletion_protection=true`, disable it before destroying.
