data "aws_ami" "amazon_linux_2023" {
  most_recent = true

  owners = ["137112412989"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.jenkins_security_group_id]
  iam_instance_profile   = var.jenkins_instance_profile_name
  key_name               = var.key_pair_name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

 user_data = <<-EOF
#!/bin/bash
set -e

# Update system
yum update -y

# Install Java 21 (NOT 17)
yum install -y java-21-amazon-corretto

# Set Java 21 as default
alternatives --set java /usr/lib/jvm/java-21-amazon-corretto.x86_64/bin/java

# Verify Java
java -version

# Install Jenkins repo
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key

# Install Jenkins
yum install -y jenkins

# Install Git + Docker
yum install -y git docker

# Start Docker
systemctl start docker
systemctl enable docker

# Give Jenkins Docker access
usermod -aG docker jenkins

# Start Jenkins
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins

# Wait for Jenkins
sleep 20

# Print initial password
cat /var/lib/jenkins/secrets/initialAdminPassword

EOF

  tags = {
    Name = "${var.name_prefix}-jenkins"
  }
}