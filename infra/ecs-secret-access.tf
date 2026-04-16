resource "aws_iam_policy" "ecs_db_secret_access" {
  name        = "order-platform-ecs-db-secret-access"
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