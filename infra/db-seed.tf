resource "null_resource" "db_seed" {
  depends_on = [
    module.rds,
    module.jenkins
  ]

  provisioner "remote-exec" {
    inline = [
      "sudo dnf install -y postgresql15 git jq awscli",
      "cd /home/ec2-user",
      "rm -rf order-platform",
      "git clone https://github.com/muhammadhassan120/order-platform.git",
      "cd order-platform",
      "sleep 60",
      "SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id ${module.rds.db_secret_arn} --region us-east-2 --query SecretString --output text)",
      "DB_USER=$(echo \"$SECRET_JSON\" | jq -r .username)",
      "DB_PASS=$(echo \"$SECRET_JSON\" | jq -r .password)",
      "DB_HOST=$(echo '${module.rds.db_endpoint}' | cut -d':' -f1)",
      "psql \"host=$DB_HOST port=5432 dbname=mydb user=$DB_USER password=$DB_PASS sslmode=require\" -f scripts/seed-db.sql"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("D:/key-pairs/order-platform-key.pem")
      host        = module.jenkins.public_ip
    }
  }
}