resource "null_resource" "db_seed" {
  depends_on = [
    module.rds,
    module.jenkins
  ]

  provisioner "remote-exec" {
    inline = [
      # Clean DNF cache to avoid stale/corrupted package errors
      "sudo dnf clean packages",
      "sudo dnf clean metadata",

      # Install required packages with retry logic
      "for i in 1 2 3; do sudo dnf install -y postgresql15 git jq awscli && break || sleep 10; done",

      # Verify git installed successfully before proceeding
      "which git || (echo 'ERROR: git failed to install' && exit 1)",
      "which psql || (echo 'ERROR: postgresql15 failed to install' && exit 1)",

      # Clone the repository
      "cd /home/ec2-user",
      "rm -rf order-platform",
      "git clone https://github.com/muhammadhassan120/order-platform.git",
      "cd order-platform",

      # Wait for RDS to be fully ready to accept connections
      "echo 'Waiting for RDS to be ready...'",
      "sleep 60",

      # Fetch DB credentials from Secrets Manager
      "SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id ${module.rds.db_secret_arn} --region us-east-2 --query SecretString --output text)",
      "DB_USER=$(echo \"$SECRET_JSON\" | jq -r .username)",
      "DB_PASS=$(echo \"$SECRET_JSON\" | jq -r .password)",
      "DB_HOST=$(echo '${module.rds.db_endpoint}' | cut -d':' -f1)",

      # Verify seed file exists before running
      "ls scripts/seed-db.sql || (echo 'ERROR: seed-db.sql not found in repo' && exit 1)",

      # Run the seed script
      "PGPASSWORD=\"$DB_PASS\" psql \"host=$DB_HOST port=5432 dbname=mydb user=$DB_USER sslmode=require\" -f scripts/seed-db.sql"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("D:/key-pairs/order-platform-key.pem")
      host        = module.jenkins.public_ip
    }
  }
}
