# ==================== SQS QUEUES ====================

resource "aws_sqs_queue" "dead_letter_queue" {
  name                      = "${var.name_prefix}-dlq"
  message_retention_seconds = 1209600

  tags = {
    Name = "${var.name_prefix}-dlq"
  }
}

resource "aws_sqs_queue" "order_queue" {
  name                       = "${var.name_prefix}-queue"
  visibility_timeout_seconds = 120
  message_retention_seconds  = 345600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter_queue.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "${var.name_prefix}-queue"
  }
}

# ==================== DYNAMODB AUDIT TABLE ====================

resource "aws_dynamodb_table" "audit_trail" {
  name         = "${var.name_prefix}-audit-trail"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "PK"
  range_key    = "SK"

  attribute {
    name = "PK"
    type = "S"
  }

  attribute {
    name = "SK"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name = "${var.name_prefix}-audit-table"
  }
}

# ==================== LAMBDA PACKAGE ====================
# IMPORTANT:
# We are NOT building Lambda with local-exec anymore.
# We are zipping the already-prepared lambda_build folder that is stored in the repo.
# This avoids Windows/Linux shell issues during terraform apply.

data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_build"
  output_path = "${path.module}/lambda_function.zip"
}

# ==================== LAMBDA FUNCTION ====================

resource "aws_lambda_function" "order_processor" {
  function_name = "${var.name_prefix}-order-processor"
  runtime       = "python3.12"
  handler       = "handler.handler"
  role          = var.lambda_role_arn
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      AUDIT_TABLE    = aws_dynamodb_table.audit_trail.name
      DB_SECRET_ARN  = var.db_secret_arn
      DB_HOST        = var.db_host
      DB_NAME        = var.db_name
      DB_PORT        = tostring(var.db_port)
      INVOICE_BUCKET = var.invoice_bucket_id
      SNS_TOPIC_ARN  = var.sns_topic_arn
    }
  }

  depends_on = [
    aws_dynamodb_table.audit_trail
  ]
}

# ==================== TRIGGER (SQS -> LAMBDA) ====================

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.order_queue.arn
  function_name    = aws_lambda_function.order_processor.arn
  batch_size       = 5
  enabled          = true
}