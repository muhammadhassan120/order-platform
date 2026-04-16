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
dnf update -y

# Install Java 21
dnf install -y java-21-amazon-corretto

# Set Java 21 default
alternatives --set java /usr/lib/jvm/java-21-amazon-corretto.x86_64/bin/java

# Install Jenkins repo
wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key

# Install Jenkins
dnf install -y jenkins

# Install Git, Docker, AWS CLI, jq
dnf install -y git docker awscli jq

# Install Node.js 20 + npm
curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
dnf install -y nodejs

# Start and enable Docker
systemctl enable docker
systemctl start docker

# Give Jenkins access to Docker
usermod -aG docker jenkins

# Start and enable Jenkins
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins

# Wait a bit
sleep 20

# Show versions for debugging
java -version
node -v
npm -v
aws --version
jq --version
docker --version

# Print Jenkins initial password
cat /var/lib/jenkins/secrets/initialAdminPassword || true
EOF

  tags = {
    Name = "${var.name_prefix}-jenkins"
  }
}