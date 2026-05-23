# Order Platform Runbook

## Flow

```text
Browser/UI -> CloudFront HTTPS -> ALB HTTP -> ECS order-api -> RDS
order-api -> SQS -> Lambda order-processor -> RDS/DynamoDB/S3/SES/SNS
Jenkins -> ECR immutable image tags -> ECS
Jenkins -> packaged Lambda zip -> Lambda
```

CloudFront redirects viewers to HTTPS. The ALB origin remains HTTP.

## API Behavior

`POST /orders` accepts:

```json
{
  "customer_email": "test@example.com",
  "items": [{ "product_id": "SMOKE-001", "qty": 1 }]
}
```

Rules:

- `customer_email` must be a valid email.
- `items` must be a non-empty array.
- `qty` must be a positive integer.
- Missing product or insufficient stock returns conflict.
- SQS publish failure after DB commit marks the order `FAILED` and restores stock.

API auth is off by default with `AUTH_ENABLED=false`.

## Common Commands

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

Check order:

```bash
curl http://<alb_dns_name>/orders/<order_id>
```

Open UI:

```text
https://<cloudfront_distribution_domain_name>/
```

## Terraform

Local validation:

```bash
bash scripts/package-lambda.sh
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra init -backend=false
terraform -chdir=infra validate
terraform -chdir=infra plan -refresh=false -input=false -var-file=environments/dev.tfvars
```

Jenkins infra deployment uses `jenkins/Jenkinsfile.infra`. It only supports `dev`, packages Lambda before planning, creates/checks the S3 state bucket `order-platform-tfstate-<account-id>`, writes `infra/backend.generated.tf`, and runs Terraform with backend config.

## Jenkins

App pipeline: `jenkins/Jenkinsfile`

Main stages:

- `npm ci` and API tests
- Lambda pytest checks
- `scripts/package-lambda.sh`
- Docker build and immutable ECR push
- Lambda code update
- ECS deploy
- smoke test requiring `POST /orders` to return `201`

Required Jenkins plugins include Pipeline, Git, and Workspace Cleanup for `cleanWs()`.

Rollback:

```bash
AWS_REGION=us-east-2 ./jenkins/scripts/rollback.sh <previous-image-tag>
```

The rollback script computes the active AWS account and ECR URL dynamically.

## Lambda

Source of truth:

```text
services/order-processor/
```

Package build target:

```text
infra/modules/async/lambda_build/
```

Refresh package source/dependencies:

```bash
bash scripts/package-lambda.sh
```

Retry behavior:

- Completed orders are skipped.
- Payment references and invoice object keys are deterministic per order.
- SES and SNS failures are logged after completion and do not force SQS retries.

## Database Seed

Terraform seeds through SSM on the Jenkins EC2 instance. No local SSH key path is required for seeding.

Manual fallback from Jenkins:

```bash
git clone https://github.com/client-org/order-platform.git order-platform
cd order-platform
PGPASSWORD="<db-password>" psql \
  "host=<rds-host> port=5432 dbname=mydb user=<db-user> sslmode=require" \
  -f scripts/seed-db.sql
```

Seeded products:

```text
SMOKE-001
PROD-001
PROD-002
PROD-003
PROD-004
```

## Troubleshooting

`/health` returns `503`: check RDS reachability, DB secret ARN, and ECS security group egress.

Order returns `400`: check email, item list, and integer `qty`.

Order returns conflict: product is missing or stock is insufficient.

Order returns SQS error: check queue URL, ECS IAM permissions, and SQS health; the order should be `FAILED` with stock restored.

Order stays `PENDING`: check Lambda CloudWatch logs, event source mapping, RDS connectivity, and SQS DLQ.

Invoice missing: confirm the order is `COMPLETED`, Lambda S3 permission exists, and the object key is under `invoices/<order_id>/`.

Email missing: confirm SES sender is verified in `us-east-2`; sandbox accounts may also require verified recipients.

Jenkins cannot push image: check Jenkins IAM, Docker availability, ECR repo name, and `aws sts get-caller-identity`.

Jenkins `cleanWs` fails: install the Workspace Cleanup plugin.

## Verification Checklist

- Terraform fmt, validate, and plan pass.
- API tests pass.
- Lambda pytest tests pass.
- Lambda package script runs.
- Jenkins app pipeline succeeds.
- `/health` returns `200`.
- Inventory loads.
- `POST /orders` returns `201`.
- Order becomes `COMPLETED`.
- Invoice exists in S3.
- Audit event exists in DynamoDB.
- SQS DLQ stays empty during normal testing.
