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

resource "aws_dynamodb_table" "audit_trail" {
  name         = "${var.name_prefix}-audit-trail"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  tags = {
    Name = "${var.name_prefix}-audit-trail"
  }
}

data "archive_file" "lambda_package" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_build"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "order_processor" {
  function_name    = "${var.name_prefix}-order-processor"
  role             = var.lambda_role_arn
  runtime          = "python3.12"
  handler          = "handler.handler"
  filename         = data.archive_file.lambda_package.output_path
  source_code_hash = data.archive_file.lambda_package.output_base64sha256
  timeout          = 60
  memory_size      = 256

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      AUDIT_TABLE     = aws_dynamodb_table.audit_trail.name
      SNS_TOPIC_ARN   = var.sns_topic_arn
      INVOICE_BUCKET  = var.invoice_bucket_id
      DB_SECRET_ARN   = var.db_secret_arn
      DB_HOST         = var.db_host
      DB_NAME         = var.db_name
      DB_PORT         = tostring(var.db_port)
      OPS_ALERT_TOPIC = var.ops_alert_topic_arn
      SES_FROM_EMAIL  = var.ses_from_email
    }
  }

  depends_on = [
    aws_dynamodb_table.audit_trail
  ]
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.order_queue.arn
  function_name    = aws_lambda_function.order_processor.arn
  batch_size       = 1
  enabled          = true
}