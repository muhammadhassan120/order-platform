resource "aws_iam_policy" "jenkins_db_secret_access" {
  name        = "order-platform-jenkins-db-secret-access"
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