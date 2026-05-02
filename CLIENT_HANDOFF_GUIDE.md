# Client Handoff Guide

This is the clean guide for running and handing over the Order Platform project.

The language is intentionally simple. Follow the steps in order. Do not skip the "before Terraform apply" section.

## 1. What This Project Does

This project is an AWS event-driven order processing platform.

Simple flow:

1. A user opens the website.
2. The website talks to the Order API.
3. The Order API reads products from PostgreSQL.
4. When the user creates an order, the API saves the order in PostgreSQL.
5. The API sends an order message to SQS.
6. Lambda receives the SQS message and processes the order.
7. Lambda marks the order as completed.
8. Lambda writes an audit record to DynamoDB.
9. Lambda creates an invoice file in S3.
10. The website shows live order progress.
11. After completion, the website shows a Download Invoice button.
12. The invoice download uses a short-lived pre-signed S3 URL.

Main AWS flow:

```text
Browser
  -> CloudFront
  -> Application Load Balancer
  -> ECS Fargate Order API
  -> RDS PostgreSQL

Order API
  -> SQS
  -> Lambda
  -> RDS, DynamoDB, S3, SES, SNS

Jenkins
  -> Builds Docker image
  -> Pushes image to ECR
  -> Updates ECS service
```

## 2. Files I Checked

This guide is based on the current project files, including:

- `infra`
- `infra/module`
- `services/order-api`
- `services/order-processor`
- `jenkins`
- `scripts`
- `docs`
- `INSTRUCTION.txt`
- `PLACEHOLDERS.md`
- `README.md`
- `README1.md`
- `README-IMP`

Important note:

Some older notes are rough or outdated. For example, old docs mention a fixed Jenkins password. The current Jenkins setup does not bypass the Jenkins setup wizard. Use this file as the final client guide.

## 3. What The Client Needs Before Starting

The client needs these things ready:

1. AWS account
2. AWS CLI installed
3. Terraform installed
4. Git installed
5. A GitHub repository for this project
6. An EC2 key pair
7. An S3 bucket for Terraform state
8. A verified SES sender email

Use this AWS region:

```text
us-east-2
```

Do not change the region unless you are ready to update many files.

## 4. Install And Login Tools

Check AWS login:

```bash
aws sts get-caller-identity
```

Copy the 12 digit AWS account ID from the output. You need it for Jenkins ECR settings.

Check Terraform:

```bash
terraform version
```

This project expects Terraform `1.5.0` or newer.

## 5. Before Terraform Apply

Do all steps in this section before running `terraform apply`.

### Step 1: Create Terraform State S3 Bucket

Create one S3 bucket manually in AWS.

This bucket stores Terraform state. It is not the invoice bucket.

Example bucket name:

```text
client-order-platform-tfstate-123456789012
```

Use a unique name. S3 bucket names must be globally unique.

Open:

```text
infra/versions.tf
```

Replace this:

```hcl
bucket = "event-driven-state-key"
```

With the client's bucket name:

```hcl
bucket = "client-order-platform-tfstate-123456789012"
```

Keep this unless you intentionally want a different state path:

```hcl
key = "event-driven/terraform.tfstate"
```

### Step 2: Update Jenkins Infra State Bucket

Open:

```text
jenkins/Jenkinsfile.infra
```

Replace:

```groovy
TF_STATE_BUCKET = 'event-driven-state-key'
```

With the same Terraform state bucket name.

Important:

The first deployment should be done locally with Terraform. The infra Jenkinsfile is optional. It also needs Terraform installed on the Jenkins server before it can be used.

### Step 3: Create EC2 Key Pair

Go to AWS Console:

```text
EC2 -> Key Pairs -> Create key pair
```

Recommended key pair name:

```text
order-platform-key
```

Download the `.pem` file and keep it safe.

Important:

The AWS key pair name is usually `order-platform-key`.

The downloaded file may be `order-platform-key.pem`.

These are related, but they are not the same value.

### Step 4: Update Jenkins Key Pair Name

Open:

```text
infra/jenkins.tf
```

Current value:

```hcl
key_pair_name = "order-platform-key"
```

If the client created the same key pair name, keep it.

If the client used another key pair name, replace it with the exact AWS key pair name.

### Step 5: Update Local PEM File Path

Open:

```text
infra/db-seed.tf
```

Current value:

```hcl
private_key = file("D:/key-pairs/order-platform-key.pem")
```

Replace it with the real path on the client's machine.

Windows example:

```hcl
private_key = file("C:/Users/Client/Downloads/order-platform-key.pem")
```

macOS or Linux example:

```hcl
private_key = file("/Users/client/.ssh/order-platform-key.pem")
```

If this path is wrong, Terraform can fail during database seed.

### Step 6: Update Admin IP

This controls who can SSH into Jenkins and open Jenkins in the browser.

Find the client's public IP by searching:

```text
what is my ip
```

Then add `/32` at the end.

Example:

```text
203.0.113.10/32
```

Open:

```text
infra/security.tf
```

Current value:

```hcl
admin_cidr = "182.189.96.68/32"
```

Replace it with the client's public IP CIDR.

If this is wrong, Jenkins will not open on port `8080`.

### Step 7: Update SES Sender Email

The Lambda sends order confirmation emails through SES.

The sender email must be verified in SES in `us-east-2`.

Open these files:

```text
infra/terraform.tfvars
infra/environments/dev.tfvars
```

Current value:

```hcl
ses_from_email = "hammadmuqaddam@gmail.com"
```

Replace it with the client's verified email.

Example:

```hcl
ses_from_email = "orders@clientdomain.com"
```

If the AWS account is in SES sandbox, test customer emails may also need to be verified.

### Step 8: Update GitHub Repository URL

Push this project to the client's GitHub repository before Terraform apply.

The automatic database seed step clones the repository during `terraform apply`.

Open:

```text
infra/jenkins.tf
infra/db-seed.tf
```

Replace:

```text
https://github.com/muhammadhassan120/order-platform.git
```

With the client's GitHub repository URL.

Example:

```text
https://github.com/client-org/order-platform.git
```

Important:

If the repository is private, automatic database seed may fail unless the Jenkins EC2 instance can clone it. For the simplest delivery, use a public repository during initial setup, or seed the database manually after apply.

### Step 9: Update ECR URL In Jenkins Files

Get AWS account ID:

```bash
aws sts get-caller-identity --query Account --output text
```

Open:

```text
jenkins/Jenkinsfile
jenkins/scripts/rollback.sh
```

Replace the old account ID:

```text
992382749898
```

With the client's AWS account ID.

Example ECR URL:

```text
123456789012.dkr.ecr.us-east-2.amazonaws.com/order-platform-repo
```

Do not change `order-platform-repo` unless you also change it in Terraform.

### Step 10: Check Invoice Bucket Name

The invoice bucket is created from this file:

```text
infra/s3 + sns .tf
```

Current prefix:

```hcl
name_prefix = "order-platform"
```

This creates this S3 bucket:

```text
order-platform-invoices
```

S3 bucket names are global. If this bucket name is already taken, Terraform apply will fail.

If needed, change the prefix to a client-specific value:

```hcl
name_prefix = "client-order-platform"
```

That would create:

```text
client-order-platform-invoices
```

Use only lowercase letters, numbers, and hyphens for S3 bucket names.

### Step 11: Optional Cleanup Before Sharing

These are not needed for client setup:

- `node_modules`
- `.terraform`
- old local logs
- old `.zip` files
- `infra/errored.tfstate`

Do not use `infra/errored.tfstate` for deployment. It is an old failed state file and contains old AWS account values.

## 6. Push Code To GitHub

From the project root:

```bash
git init
git add .
git commit -m "Initial order platform delivery"
git branch -M main
git remote add origin https://github.com/client-org/order-platform.git
git push -u origin main
```

If the repo already exists, use the normal Git workflow.

Make sure the pushed code already contains the client values from the previous section.

## 7. Run Terraform

From the project root:

```bash
cd infra
terraform init -reconfigure
terraform fmt
terraform validate
terraform plan
terraform apply
```

When Terraform asks for approval, type:

```text
yes
```

Do not close the terminal while Terraform is running.

Terraform creates:

- VPC
- Public and private subnets
- Internet Gateway
- NAT Gateway
- Security groups
- IAM roles and policies
- ECR repository
- ECS cluster, task definition, and service
- Application Load Balancer
- RDS PostgreSQL database
- Secrets Manager database secret
- SQS queue and DLQ
- Lambda order processor
- DynamoDB audit table
- S3 invoice bucket
- SNS topics
- CloudFront distribution
- CloudWatch dashboard and alarms
- Jenkins EC2 instance
- Database seed attempt

Important:

It is normal if ECS is not healthy before Jenkins builds and pushes the first Docker image to ECR.

## 8. Save Terraform Outputs

After apply completes, run:

```bash
terraform output
```

Save these values:

- `jenkins_public_ip`
- `alb_dns_name`
- `cloudfront_distribution_domain_name`
- `invoice_bucket_name`
- `order_queue_url`
- `lambda_function_name`
- `ecs_cluster_name`
- `ecs_service_name`

You will use them during setup and testing.

## 9. After Terraform Apply: Open Jenkins

Open Jenkins:

```text
http://<jenkins_public_ip>:8080
```

Current Jenkins behavior:

Jenkins setup wizard is not bypassed. This is correct.

You must unlock Jenkins and install plugins yourself.

To get the initial admin password, SSH into Jenkins:

```bash
ssh -i "<path-to-pem-file>" ec2-user@<jenkins_public_ip>
```

Then run:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

If you want to check the bootstrap log:

```bash
sudo tail -n 80 /var/log/jenkins-bootstrap.log
```

Paste the password into the Jenkins page.

Then choose:

```text
Install suggested plugins
```

This is important. Pipeline jobs will not work properly without the needed plugins.

After plugin installation, create the Jenkins admin user.

## 10. Jenkins Plugins To Check

Suggested plugins usually install what is needed.

After setup, make sure Jenkins can create a Pipeline job.

If something is missing, install these plugins from:

```text
Manage Jenkins -> Plugins
```

Recommended plugins:

- Pipeline
- Git
- GitHub
- Credentials
- Workspace Cleanup

Why Workspace Cleanup matters:

The current `jenkins/Jenkinsfile` uses:

```groovy
cleanWs()
```

If Jenkins says `cleanWs` is unknown, install the Workspace Cleanup plugin.

## 11. Create Jenkins App Pipeline

In Jenkins:

1. Click `New Item`.
2. Enter name:

```text
order-platform-app
```

3. Select `Pipeline`.
4. Click `OK`.
5. Under Pipeline, choose:

```text
Pipeline script from SCM
```

6. SCM:

```text
Git
```

7. Repository URL:

```text
https://github.com/client-org/order-platform.git
```

8. Branch:

```text
*/main
```

9. Script Path:

```text
jenkins/Jenkinsfile
```

10. Save.
11. Click `Build Now`.

The pipeline will:

1. Checkout code.
2. Run Node.js tests.
3. Build Docker image.
4. Push Docker image to ECR.
5. Register new ECS task definition.
6. Update ECS service.
7. Run smoke tests.

No manual AWS access keys are normally needed inside Jenkins because the Jenkins EC2 instance has an IAM role.

## 12. If Jenkins Pipeline Fails

Use these quick checks.

### ECR Login Fails

Check:

```text
jenkins/Jenkinsfile
jenkins/scripts/rollback.sh
```

Make sure the ECR URL has the client's AWS account ID.

### Docker Permission Fails

SSH into Jenkins:

```bash
ssh -i "<path-to-pem-file>" ec2-user@<jenkins_public_ip>
```

Run:

```bash
sudo systemctl status docker
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

Then run the pipeline again.

### npm Command Not Found

SSH into Jenkins and run:

```bash
sudo dnf install -y nodejs npm
node -v
npm -v
sudo systemctl restart jenkins
```

Then run the pipeline again.

### cleanWs Error

Install the Workspace Cleanup plugin in Jenkins.

### Git Checkout Fails

If the GitHub repo is private, add GitHub credentials in Jenkins.

For the easiest client setup, use a public repo for the first deployment.

## 13. Test The Application

Test the health endpoint:

```bash
curl http://<alb_dns_name>/health
```

Expected:

```json
{
  "status": "healthy"
}
```

Open the website:

```text
https://<cloudfront_distribution_domain_name>/
```

You can also test through the ALB:

```text
http://<alb_dns_name>/
```

In the website:

1. Click `Check Health`.
2. Click `Load Inventory`.
3. Select or type a product ID.
4. Enter a customer email.
5. Click `Create Order`.
6. Watch the live order pipeline.
7. Wait for the order to become `COMPLETED`.
8. Click `Get Order` if needed.
9. After completion, click `Download Invoice`.

The invoice link is a pre-signed S3 URL. It expires after about 5 minutes.

## 14. Test With curl

Create an order:

```bash
curl -X POST http://<alb_dns_name>/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customer_email": "test@example.com",
    "items": [
      { "product_id": "SMOKE-001", "qty": 1 }
    ]
  }'
```

Check order:

```bash
curl http://<alb_dns_name>/orders/<order_id>
```

Get invoice link after order completion:

```bash
curl http://<alb_dns_name>/orders/<order_id>/invoice
```

The invoice endpoint returns JSON with:

```text
invoice_url
expires_in
invoice_key
```

Open `invoice_url` in a browser to download the invoice.

## 15. Database Seed

Terraform tries to seed the database automatically through:

```text
infra/db-seed.tf
```

It SSHs into Jenkins, clones the repo, reads the DB secret, and runs:

```text
scripts/seed-db.sql
```

The seed creates:

- `products`
- `orders`

It also inserts sample products:

- `PROD-001`
- `PROD-002`
- `PROD-003`
- `PROD-004`
- `SMOKE-001`

If inventory does not load, the database was probably not seeded.

## 16. Manual Database Seed Fallback

Use this if automatic seed fails.

SSH into Jenkins:

```bash
ssh -i "<path-to-pem-file>" ec2-user@<jenkins_public_ip>
```

Install tools:

```bash
sudo dnf install -y postgresql15 git jq awscli
```

Clone the repo:

```bash
cd ~
rm -rf order-platform
git clone https://github.com/client-org/order-platform.git
cd order-platform
```

Find the RDS endpoint in AWS Console:

```text
RDS -> Databases -> order-platform-latet-db -> Endpoint
```

Find the database secret in AWS Console:

```text
Secrets Manager
```

Current secret name pattern:

```text
order-platform-latet-db-credentials-order-processing-secret-latest-app
```

Copy the real password from the secret.

Then run:

```bash
psql "host=<RDS_ENDPOINT> port=5432 dbname=mydb user=appuser password=<REAL_DB_PASSWORD> sslmode=require" -f scripts/seed-db.sql
```

Verify tables:

```bash
psql "host=<RDS_ENDPOINT> port=5432 dbname=mydb user=appuser password=<REAL_DB_PASSWORD> sslmode=require"
```

Inside `psql`:

```sql
\dt
\q
```

Expected tables:

```text
orders
products
```

## 17. Async Processing Checks

If orders stay `PENDING`, check these in AWS:

1. SQS queue:

```text
order-platform-queue
```

2. SQS dead letter queue:

```text
order-platform-dlq
```

3. Lambda:

```text
order-platform-order-processor
```

4. Lambda logs:

```text
CloudWatch -> Log groups -> /aws/lambda/order-platform-order-processor
```

5. DynamoDB table:

```text
order-platform-audit-trail
```

6. S3 invoice bucket:

```text
<invoice_bucket_name>
```

Normal successful order:

- SQS receives message.
- Lambda runs.
- Order becomes `COMPLETED`.
- S3 gets an invoice file under `invoices/`.
- DynamoDB gets an audit item.

## 18. Common Problems And Simple Fixes

### Jenkins Does Not Open

Check:

- `infra/security.tf` admin CIDR is correct.
- Your public IP did not change.
- EC2 security group allows port `8080`.
- Jenkins service is running.

SSH into Jenkins:

```bash
sudo systemctl status jenkins
sudo tail -n 100 /var/log/jenkins-bootstrap.log
```

### Jenkins Shows Setup Wizard

This is correct.

Do not bypass it.

Use the initial password and install suggested plugins.

### Pipeline Job Type Missing

The Pipeline plugin is missing.

Go to:

```text
Manage Jenkins -> Plugins
```

Install Pipeline and Git plugins.

### Health Check Returns 503

Usually this means the API cannot connect to the database.

Check:

- RDS is available.
- DB secret exists.
- ECS task has `DB_SECRET_ARN`.
- RDS security group allows ECS.
- Database was seeded.

### Inventory Does Not Load

Most likely the database seed did not run.

Run the manual seed fallback.

### Order Creation Fails With Product Not Found

Use a seeded product ID:

```text
SMOKE-001
PROD-001
PROD-002
PROD-003
PROD-004
```

### Order Stays Pending

Check Lambda logs and SQS DLQ.

If DLQ has messages, read the message and check the Lambda error in CloudWatch.

### Invoice Button Does Not Show

The button only appears after:

- order status is `COMPLETED`
- database row has `invoice_key`
- invoice file exists in S3
- ECS task role has S3 `GetObject` permission

Current code already includes ECS S3 invoice read permission in:

```text
infra/ecs-invoice-access.tf
```

### Email Fails

Check SES:

- Sender email is verified.
- Region is `us-east-2`.
- If SES sandbox is enabled, recipient email may also need verification.

## 19. What To Change After Terraform Apply

After Terraform apply, do not randomly edit Terraform files unless something failed.

Normally, after apply you only do this:

1. Save Terraform outputs.
2. Open Jenkins.
3. Unlock Jenkins.
4. Install suggested plugins.
5. Create Jenkins admin user.
6. Create Jenkins Pipeline job.
7. Run the app pipeline.
8. Test ALB and CloudFront URLs.

For future app changes:

1. Change application code.
2. Commit and push to GitHub.
3. Run the Jenkins app pipeline.

You do not need `terraform apply` for normal app code changes.

Use Terraform again only when changing AWS infrastructure.

## 20. Important Current Values

These are the current project defaults:

| Item | Current value |
| --- | --- |
| AWS region | `us-east-2` |
| ECS cluster | `order-platform-cluster` |
| ECS service | `order-platform-service` |
| ECS container | `order-api` |
| ECS port | `3000` |
| ECR repository name | `order-platform-repo` |
| RDS database | `mydb` |
| RDS username | `appuser` |
| RDS instance name | `order-platform-latet-db` |
| SQS queue | `order-platform-queue` |
| SQS DLQ | `order-platform-dlq` |
| Lambda | `order-platform-order-processor` |
| DynamoDB table | `order-platform-audit-trail` |
| CloudWatch dashboard | `order-platform-dashboard` |
| Jenkins port | `8080` |

## 21. Files The Client Usually Edits

Before first deployment:

| File | What to edit |
| --- | --- |
| `infra/versions.tf` | Terraform state S3 bucket |
| `jenkins/Jenkinsfile.infra` | Terraform state S3 bucket if using infra pipeline |
| `infra/security.tf` | Client public IP CIDR |
| `infra/terraform.tfvars` | SES sender email |
| `infra/environments/dev.tfvars` | SES sender email |
| `infra/jenkins.tf` | EC2 key pair name and GitHub repo URL |
| `infra/db-seed.tf` | PEM path and GitHub repo URL |
| `infra/s3 + sns .tf` | Invoice bucket prefix if bucket name conflicts |
| `jenkins/Jenkinsfile` | Client AWS account ID in ECR URL |
| `jenkins/scripts/rollback.sh` | Client AWS account ID in ECR URL |

After deployment:

| Place | What to do |
| --- | --- |
| Jenkins setup wizard | Install suggested plugins |
| Jenkins Pipeline job | Point to client GitHub repo |
| AWS Console | Verify ECS, Lambda, SQS, S3, RDS |
| Website | Test health, inventory, order, invoice download |

## 22. Files The Client Should Not Normally Edit

Do not edit these unless a developer knows why:

- `services/order-api/package-lock.json`
- `services/order-api/node_modules`
- `infra/module/async/lambda_build` dependency folders
- `infra/errored.tfstate`
- generated `.zip` files
- `.terraform`

## 23. Final Delivery Checklist

Before handing to the client:

- [ ] Client AWS account ID is in Jenkins files.
- [ ] Terraform state bucket is changed.
- [ ] SES sender email is changed and verified.
- [ ] Admin CIDR is changed to client IP.
- [ ] PEM path is changed to client machine path.
- [ ] GitHub repo URLs are changed.
- [ ] Project is pushed to client GitHub repo.
- [ ] Terraform apply succeeds.
- [ ] Jenkins opens.
- [ ] Jenkins setup wizard is completed.
- [ ] Suggested plugins are installed.
- [ ] Jenkins app pipeline succeeds.
- [ ] ECS service becomes stable.
- [ ] `/health` returns healthy.
- [ ] Inventory loads.
- [ ] Create order works.
- [ ] Order becomes completed.
- [ ] Invoice file appears in S3.
- [ ] Download Invoice button works.
- [ ] DLQ is empty during normal test.

## 24. Destroy To Avoid Cost

If this is only a demo and the client does not want AWS cost, destroy the stack after testing.

First empty the invoice bucket if it contains invoices:

```bash
aws s3 rm s3://<invoice_bucket_name> --recursive
```

Then destroy:

```bash
cd infra
terraform destroy
```

Type:

```text
yes
```

CloudFront deletion can take time. Wait until Terraform finishes.

Do not delete the Terraform state bucket unless the client is completely done with the project.

## 25. One Page Quick Run

Use this only after all values are replaced.

```bash
aws sts get-caller-identity
cd infra
terraform init -reconfigure
terraform fmt
terraform validate
terraform plan
terraform apply
terraform output
```

Then:

```text
Open http://<jenkins_public_ip>:8080
Unlock Jenkins
Install suggested plugins
Create Pipeline job
Use script path jenkins/Jenkinsfile
Run Build Now
Open https://<cloudfront_distribution_domain_name>/
Test order flow
Download invoice after completion
```
