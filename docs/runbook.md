# Order Platform Runbook

## Overview
This project is an event-driven order processing platform.

Main flow:
1. User opens `/` and sees the built-in UI
2. UI or API client sends `POST /orders` to Order API
3. API writes order to PostgreSQL
4. API publishes message to SQS
5. Lambda processes order asynchronously
6. Lambda updates order status, writes audit trail, stores invoice in S3, publishes SNS notification

## Main Components
- CloudFront in front of ALB
- ALB in front of ECS Fargate service for `order-api`
- RDS PostgreSQL
- SQS queue + DLQ
- Lambda `order-processor`
- DynamoDB audit table
- S3 invoice bucket
- SNS topics for notifications and ops alerts
- Jenkins for CI/CD
- CloudWatch dashboard and alarms

## Important Environment Variables

### Order API
- `PORT`
- `AWS_REGION`
- `DB_SECRET_ARN`
- `ORDER_QUEUE_URL`
- `AUTH_ENABLED`
- `API_KEY`

### Lambda
- `AUDIT_TABLE`
- `SNS_TOPIC_ARN`
- `INVOICE_BUCKET`
- `DB_SECRET_ARN`
- `OPS_ALERT_TOPIC`

## Health Check
```bash
curl http://<alb-dns>/health
```

## Open Browser UI
```text
http://<alb-dns>/
```

Or if CloudFront is in front:
```text
https://<cloudfront-domain>/
```

## Create Order
```bash
curl -X POST http://<alb-dns>/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customer_email": "test@example.com",
    "items": [
      { "product_id": "PROD-001", "qty": 1 }
    ]
  }'
```

## Check Order
```bash
curl http://<alb-dns>/orders/1
```

## Seed Database
Run after RDS is up:
```bash
psql "host=<rds-endpoint> port=5432 dbname=<db> user=<user> password=<password> sslmode=require" -f scripts/seed-db.sql
```

## Jenkins Pipelines

### App pipeline
File:
- `jenkins/Jenkinsfile`

Stages:
- checkout
- test
- docker build/push
- ECS deploy
- smoke test
- archive

### Infra pipeline
File:
- `jenkins/Jenkinsfile.infra`

Stages:
- terraform init
- terraform plan
- approval
- terraform apply/destroy

## Smoke Test
```bash
./jenkins/scripts/smoke-test.sh
```

## Rollback
```bash
./jenkins/scripts/rollback.sh <previous-image-tag>
```

## Common Failure Cases

### 1. `/health` returns 503
Possible reasons:
- RDS not reachable
- wrong DB secret ARN
- secret JSON format wrong
- security group issue

### 2. Order creation fails with 409
Possible reasons:
- product not found
- not enough stock

### 3. Orders remain stuck in `PENDING`
Possible reasons:
- SQS trigger not attached
- Lambda failing
- Lambda cannot connect to RDS
- DLQ filling up

### 4. Jenkins deploy fails
Possible reasons:
- ECR login issue
- missing IAM permissions
- wrong task definition/service name
- jq missing on Jenkins server

## Manual Verification Checklist
- `/health` returns 200
- UI opens at `/`
- inventory loads
- create order works
- order row created in RDS
- SQS receives message
- Lambda processes message
- order becomes `COMPLETED`
- invoice written to S3
- audit event written to DynamoDB
- SNS notification published
