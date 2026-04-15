# Placeholders to Replace

## jenkins/Jenkinsfile
- `ECR_REPO = credentials('ecr-repo-url')`
  - Replace only if your Jenkins credential ID is different.
- `ARTIFACTS_S3 = 'PUT_YOUR_ARTIFACTS_BUCKET_NAME_HERE'`
  - Replace with your artifacts bucket name.
- `TASK_CONTAINER = 'order-api'`
  - Replace only if your ECS task container name is different.

## jenkins/Jenkinsfile.infra
- `TF_STATE_BUCKET = 'PUT_YOUR_TERRAFORM_STATE_BUCKET_HERE'`
  - Replace with your Terraform state S3 bucket.

## jenkins/scripts/rollback.sh
- `--repository-name PUT_YOUR_ECR_REPOSITORY_NAME_HERE`
  - Replace with your ECR repository name, not full URL.
- `ECR_REPO:=PUT_YOUR_ECR_REPO_URL_HERE`
  - Replace with your full ECR repo URL.

## docs/runbook.md
Replace manual values when documenting or testing:
- `<alb-dns>`
- `<cloudfront-domain>`
- `<rds-endpoint>`
- `<db>`
- `<user>`
- `<password>`
