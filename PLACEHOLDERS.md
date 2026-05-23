# Current Deployment Values

Only these values are expected to be client-specific.

## Terraform Values

Files:

```text
infra/terraform.tfvars
infra/environments/dev.tfvars
```

Current demo values:

```hcl
aws_region      = "us-east-2"
name_prefix     = "order-platform"
rds_name_prefix = "order-platform-latet"
admin_cidr      = "182.189.94.102/32"
key_pair_name   = "order-platform-key"
repo_url        = "https://github.com/muhammadhassan120/order-platform.git"
db_name         = "mydb"
db_username     = "appuser"
ses_from_email  = "hammadmuqaddam@gmail.com"
```

For another client, replace:

```text
admin_cidr
key_pair_name
repo_url
ses_from_email
```

Change `name_prefix` or `rds_name_prefix` only before the first apply.

## Terraform Backend

There is no hardcoded backend bucket in `infra/versions.tf`.

Jenkins infra pipeline creates/checks:

```text
order-platform-tfstate-<active-aws-account-id>
```

Local deployments should generate `infra/backend.generated.tf` and pass backend config during `terraform init`.

## Jenkins Values

Jenkins computes the active AWS account ID with:

```bash
aws sts get-caller-identity
```

No ECR account ID placeholder should be edited manually. Keep these names aligned with Terraform if renamed:

```text
ECR_REPOSITORY = order-platform-repo
ECS_CLUSTER    = order-platform-cluster
ECS_SERVICE    = order-platform-service
TASK_CONTAINER = order-api
LAMBDA_FUNCTION = order-platform-order-processor
```
