data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["137112412989"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
}

resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.medium"
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.jenkins_security_group_id]
  iam_instance_profile        = var.jenkins_instance_profile_name
  key_name                    = var.key_pair_name
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    exec > >(tee /var/log/jenkins-bootstrap.log) 2>&1

    echo "===== START JENKINS SETUP ====="
    sleep 20

    retry() {
      local tries="$1"
      shift
      local delay=10
      local attempt=1

      until "$@"; do
        if [ "$attempt" -ge "$tries" ]; then
          echo "Command failed after $attempt attempts: $*" >&2
          return 1
        fi

        echo "Attempt $attempt failed: $*" >&2
        dnf clean all || true
        rm -rf /var/cache/dnf/* || true
        sleep "$delay"
        attempt=$((attempt + 1))
      done
    }

    refresh_dnf_cache() {
      dnf clean all || true
      rm -rf /var/cache/dnf/* || true
      retry 5 dnf makecache --refresh
    }

    dnf_install() {
      refresh_dnf_cache
      retry 5 dnf install -y "$@"
    }

    refresh_dnf_cache
    retry 5 dnf update -y

    dnf_install \
      git \
      docker \
      jq \
      wget \
      unzip \
      tar \
      postgresql15 \
      awscli \
      java-21-amazon-corretto

    dnf_install nodejs || echo "Node.js install failed; continuing because Jenkins does not require it to start"

    alternatives --set java /usr/lib/jvm/java-21-amazon-corretto.x86_64/bin/java

    java -version
    node -v || true
    git --version
    docker --version
    psql --version

    systemctl enable docker
    systemctl start docker

    usermod -aG docker ec2-user

    wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/rpm-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    sed -i 's/^repo_gpgcheck=.*/repo_gpgcheck=0/' /etc/yum.repos.d/jenkins.repo

    dnf_install jenkins

    usermod -aG docker jenkins

    LOCAL_JENKINS_URL="http://127.0.0.1:8080"

    systemctl daemon-reload
    systemctl enable jenkins
    systemctl restart jenkins

    for i in {1..120}; do
      if curl -fsS "$LOCAL_JENKINS_URL/login" >/dev/null; then
        echo "Jenkins is up"
        break
      fi
      sleep 5
    done

    for i in {1..120}; do
      if [ -f /var/lib/jenkins/secrets/initialAdminPassword ]; then
        echo "Jenkins setup wizard is ready"
        break
      fi
      sleep 2
    done

    echo "Jenkins initial admin password:"
    cat /var/lib/jenkins/secrets/initialAdminPassword

    echo "===== JENKINS SETUP COMPLETE ====="
  EOF

  tags = {
    Name = "${var.name_prefix}-jenkins"
  }
}
