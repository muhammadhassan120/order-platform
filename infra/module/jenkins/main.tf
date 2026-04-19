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

    dnf clean all
    dnf makecache
    dnf update -y

    dnf install -y \
      git \
      docker \
      jq \
      wget \
      unzip \
      tar \
      postgresql15 \
      awscli \
      nodejs \
      java-21-amazon-corretto

    alternatives --set java /usr/lib/jvm/java-21-amazon-corretto.x86_64/bin/java

    java -version
    node -v
    git --version
    docker --version
    psql --version

    systemctl enable docker
    systemctl start docker

    usermod -aG docker ec2-user

    wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/rpm-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key || true

    dnf clean all
    dnf makecache
    dnf install -y jenkins

    usermod -aG docker jenkins

    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)

    PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
      -s http://169.254.169.254/latest/meta-data/public-ipv4)

    PUBLIC_JENKINS_URL="http://$PUBLIC_IP:8080"
    LOCAL_JENKINS_URL="http://127.0.0.1:8080"

    mkdir -p /var/lib/jenkins/init.groovy.d

    cat > /var/lib/jenkins/init.groovy.d/01-security.groovy <<'GROOVY'
    import jenkins.model.*
    import hudson.security.*
    import jenkins.install.InstallState

    def instance = Jenkins.get()

    def hudsonRealm = new HudsonPrivateSecurityRealm(false)
    if (hudsonRealm.getUser("admin") == null) {
      hudsonRealm.createAccount("admin", "Admin@12345")
    }

    instance.setSecurityRealm(hudsonRealm)

    def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
    strategy.setAllowAnonymousRead(false)
    instance.setAuthorizationStrategy(strategy)

    instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
    instance.save()
    GROOVY

    cat > /var/lib/jenkins/init.groovy.d/02-location.groovy <<GROOVY
    import jenkins.model.*

    def jlc = JenkinsLocationConfiguration.get()
    jlc.setUrl("$${PUBLIC_JENKINS_URL}/")
    jlc.save()
    GROOVY

    chown -R jenkins:jenkins /var/lib/jenkins/init.groovy.d

    mkdir -p /etc/systemd/system/jenkins.service.d
    cat > /etc/systemd/system/jenkins.service.d/override.conf <<'SYSTEMD'
    [Service]
    Environment="JAVA_OPTS=-Djava.awt.headless=true"
    SYSTEMD

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

    curl -fsS -u admin:Admin@12345 "$LOCAL_JENKINS_URL/me/api/json" >/dev/null

    echo "===== JENKINS SETUP COMPLETE ====="
  EOF

  tags = {
    Name = "${var.name_prefix}-jenkins"
  }
}