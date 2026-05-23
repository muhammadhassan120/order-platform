provider "aws" {
  region = var.aws_region
}

# Foundation
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr = "10.0.0.0/16"

  public_subnet_a_cidr  = "10.0.1.0/24"
  public_subnet_b_cidr  = "10.0.2.0/24"
  private_subnet_a_cidr = "10.0.11.0/24"
  private_subnet_b_cidr = "10.0.12.0/24"

  public_availability_zone_a  = "${var.aws_region}a"
  public_availability_zone_b  = "${var.aws_region}b"
  private_availability_zone_a = "${var.aws_region}a"
  private_availability_zone_b = "${var.aws_region}b"
}

module "security" {
  source = "./modules/security"

  vpc_id      = module.vpc.vpc_id
  name_prefix = var.name_prefix
  admin_cidr  = var.admin_cidr
}

module "alb" {
  source = "./modules/alb"

  name_prefix           = var.name_prefix
  vpc_id                = module.vpc.vpc_id
  public_subnet_ids     = module.vpc.public_subnet_ids
  alb_security_group_id = module.security.alb_security_group_id

  target_group_port     = 3000
  target_group_protocol = "HTTP"
  health_check_path     = "/health"

  listener_port     = 80
  listener_protocol = "HTTP"
}

# Data, storage, and async processing
module "s3" {
  source = "./modules/s3"

  name_prefix = var.name_prefix
}

module "sns" {
  source = "./modules/sns"

  name_prefix = var.name_prefix
}

module "rds" {
  source = "./modules/rds"

  name_prefix           = var.rds_name_prefix
  private_subnet_ids    = module.vpc.private_subnet_ids
  rds_security_group_id = module.security.rds_security_group_id
  db_name               = var.db_name
  db_username           = var.db_username
  skip_final_snapshot   = var.rds_skip_final_snapshot
  deletion_protection   = var.rds_deletion_protection
}

module "ecr" {
  source = "./modules/ecr"

  repository_name = "order-platform-repo"
}

module "async" {
  source = "./modules/async"

  name_prefix              = var.name_prefix
  private_subnet_ids       = module.vpc.private_subnet_ids
  lambda_security_group_id = module.security.lambda_security_group_id

  db_secret_arn = module.rds.db_secret_arn
  db_host       = split(":", module.rds.db_endpoint)[0]
  db_name       = var.db_name
  db_port       = 5432

  invoice_bucket_id   = module.s3.invoice_bucket_name
  invoice_bucket_arn  = module.s3.invoice_bucket_arn
  sns_topic_arn       = module.sns.order_notifications_topic_arn
  ops_alert_topic_arn = module.sns.ops_alerts_topic_arn
  ses_from_email      = var.ses_from_email
}

# ECS application
module "ecs" {
  source = "./modules/ecs"

  cluster_name          = "order-platform-cluster"
  service_name          = "order-platform-service"
  task_family           = "order-platform-task"
  container_name        = "order-api"
  container_port        = 3000
  container_image       = "${module.ecr.repository_url}:bootstrap"
  cpu                   = 256
  memory                = 512
  desired_count         = 1
  private_subnet_ids    = module.vpc.private_subnet_ids
  ecs_security_group_id = module.security.ecs_security_group_id
  target_group_arn      = module.alb.target_group_arn
  execution_role_arn    = module.security.ecs_task_execution_role_arn
  task_role_arn         = module.security.ecs_task_role_arn
  aws_region            = var.aws_region
  log_group_name        = "/ecs/order-platform"

  environment_variables = [
    {
      name  = "NODE_ENV"
      value = "production"
    },
    {
      name  = "PORT"
      value = "3000"
    },
    {
      name  = "AWS_REGION"
      value = var.aws_region
    },
    {
      name  = "ORDER_QUEUE_URL"
      value = module.async.order_queue_url
    },
    {
      name  = "AUTH_ENABLED"
      value = "false"
    },
    {
      name  = "DB_SECRET_ARN"
      value = module.rds.db_secret_arn
    },
    {
      name  = "INVOICE_BUCKET"
      value = module.s3.invoice_bucket_name
    },
    {
      name  = "DB_SSL_CA_PATH"
      value = "/app/certs/rds-global-bundle.pem"
    }
  ]

  secrets = []

  depends_on = [module.alb, module.rds, module.async]
}

module "ecs_autoscaling" {
  source = "./modules/ecs-asg"

  name_prefix  = var.name_prefix
  cluster_name = module.ecs.cluster_name
  service_name = module.ecs.service_name
  min_capacity = 1
  max_capacity = 3
  cpu_target   = 60
}

resource "aws_iam_policy" "ecs_db_secret_access" {
  name        = "${var.name_prefix}-ecs-db-secret-access"
  description = "Allow ECS execution and task roles to read the RDS secret"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = module.rds.db_secret_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_secret_access" {
  role       = split("/", module.security.ecs_task_execution_role_arn)[1]
  policy_arn = aws_iam_policy.ecs_db_secret_access.arn
}

resource "aws_iam_role_policy_attachment" "ecs_task_secret_access" {
  role       = split("/", module.security.ecs_task_role_arn)[1]
  policy_arn = aws_iam_policy.ecs_db_secret_access.arn
}

resource "aws_iam_policy" "ecs_invoice_access" {
  name        = "${var.name_prefix}-ecs-invoice-access"
  description = "Allow ECS task role to create S3 pre-signed invoice download URLs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${module.s3.invoice_bucket_arn}/invoices/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_invoice_access" {
  role       = split("/", module.security.ecs_task_role_arn)[1]
  policy_arn = aws_iam_policy.ecs_invoice_access.arn
}

# Jenkins and deployment support
module "jenkins" {
  source = "./modules/jenkins"

  name_prefix                   = var.name_prefix
  public_subnet_id              = module.vpc.public_subnet_ids[0]
  jenkins_security_group_id     = module.security.jenkins_security_group_id
  jenkins_instance_profile_name = module.security.jenkins_instance_profile_name
  key_pair_name                 = var.key_pair_name

  db_secret_arn = module.rds.db_secret_arn
  repo_url      = var.repo_url

  depends_on = [
    module.rds,
    module.async
  ]
}

resource "aws_iam_policy" "jenkins_db_secret_access" {
  name        = "${var.name_prefix}-jenkins-db-secret-access"
  description = "Allow Jenkins EC2 to read DB secret for automatic seed"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = module.rds.db_secret_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_db_secret_access_attach" {
  role       = split("/", module.security.jenkins_role_arn)[1]
  policy_arn = aws_iam_policy.jenkins_db_secret_access.arn
}

resource "aws_ssm_document" "db_seed" {
  name          = "${var.name_prefix}-db-seed"
  document_type = "Command"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Seed the order platform PostgreSQL database from the Jenkins EC2 instance"
    mainSteps = [
      {
        action = "aws:runShellScript"
        name   = "seedDatabase"
        inputs = {
          timeoutSeconds = "900"
          runCommand = [
            "set -euo pipefail",
            "sudo dnf clean packages",
            "sudo dnf clean metadata",
            "for i in 1 2 3; do sudo dnf install -y postgresql15 git jq awscli && break || sleep 10; done",
            "which git || (echo 'ERROR: git failed to install' && exit 1)",
            "which psql || (echo 'ERROR: postgresql15 failed to install' && exit 1)",
            "cd /home/ec2-user",
            "rm -rf order-platform",
            "git clone --depth 1 ${var.repo_url} order-platform",
            "cd order-platform",
            "echo 'Waiting for RDS to be ready...'",
            "sleep 60",
            "SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id ${module.rds.db_secret_arn} --region ${var.aws_region} --query SecretString --output text)",
            "DB_USER=$(echo \"$SECRET_JSON\" | jq -r .username)",
            "DB_PASS=$(echo \"$SECRET_JSON\" | jq -r .password)",
            "DB_HOST=$(echo '${module.rds.db_endpoint}' | cut -d':' -f1)",
            "ls scripts/seed-db.sql || (echo 'ERROR: seed-db.sql not found in repo' && exit 1)",
            "PGPASSWORD=\"$DB_PASS\" psql \"host=$DB_HOST port=5432 dbname=${var.db_name} user=$DB_USER sslmode=require\" -f scripts/seed-db.sql"
          ]
        }
      }
    ]
  })
}

resource "aws_ssm_association" "db_seed" {
  name = aws_ssm_document.db_seed.name

  targets {
    key    = "InstanceIds"
    values = [module.jenkins.instance_id]
  }

  depends_on = [
    module.rds,
    module.jenkins,
    aws_iam_role_policy_attachment.jenkins_db_secret_access_attach
  ]
}

# CDN and observability
module "cloudfront" {
  source = "./modules/cloudfront"

  name_prefix        = var.name_prefix
  origin_domain_name = module.alb.alb_dns_name
}

module "monitoring" {
  source = "./modules/monitoring"

  name_prefix          = var.name_prefix
  aws_region           = var.aws_region
  ecs_cluster_name     = module.ecs.cluster_name
  ecs_service_name     = module.ecs.service_name
  order_queue_name     = module.async.order_queue_name
  dlq_queue_name       = module.async.dlq_queue_name
  lambda_function_name = module.async.lambda_function_name
  alb_arn_suffix       = module.alb.alb_arn_suffix
  db_instance_id       = module.rds.db_instance_id
  ops_alerts_topic_arn = module.sns.ops_alerts_topic_arn
}
