resource "aws_iam_policy" "ecs_invoice_access" {
  name        = "order-platform-ecs-invoice-access"
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
