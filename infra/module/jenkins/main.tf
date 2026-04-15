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
yum update -y
yum install -y docker git wget unzip

wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
yum install -y java-17-amazon-corretto jenkins
systemctl enable jenkins
systemctl start jenkins

systemctl enable docker
systemctl start docker
usermod -aG docker jenkins

yum install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
yum install -y terraform

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
yum install -y nodejs

echo "Jenkins setup complete" > /home/ec2-user/setup-complete.txt
EOF

  tags = {
    Name = "${var.name_prefix}-jenkins"
  }
}