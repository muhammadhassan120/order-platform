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

  user_data_replace_on_change = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

user_data = <<-USERDATA
#!/bin/bash
set -euxo pipefail

exec > >(tee /var/log/jenkins-bootstrap.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "===== START JENKINS SETUP ====="

sleep 20

dnf clean all
dnf makecache
dnf update -y

# DO NOT install curl on AL2023 because curl-minimal is already present
dnf install -y \
  git \
  docker \
  jq \
  wget \
  unzip \
  tar \
  postgresql15 \
  awscli \
  nodejs

dnf install -y java-21-amazon-corretto
alternatives --set java /usr/lib/jvm/java-21-amazon-corretto.x86_64/bin/java || true
java -version

java -version
node -v
git --version
docker --version
psql --version

systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user || true

wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key

dnf clean all
dnf makecache
dnf install -y jenkins

systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins

for i in {1..90}; do
  if curl -fsS http://127.0.0.1:8080/login >/dev/null; then
    echo "Jenkins is up"
    break
  fi
  echo "Waiting for Jenkins to start..."
  sleep 5
done

mkdir -p /var/lib/jenkins/init.groovy.d

cat > /var/lib/jenkins/init.groovy.d/basic.groovy <<'GROOVY'
import jenkins.model.*
import hudson.security.*

def instance = Jenkins.get()

instance.setInstallState(jenkins.install.InstallState.INITIAL_SETUP_COMPLETED)

def hudsonRealm = new HudsonPrivateSecurityRealm(false)
if (hudsonRealm.getUser("admin") == null) {
  hudsonRealm.createAccount("admin", "Admin@12345")
}
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.save()
GROOVY

chown -R jenkins:jenkins /var/lib/jenkins/init.groovy.d
systemctl restart jenkins

for i in {1..90}; do
  if curl -fsS http://127.0.0.1:8080/login >/dev/null; then
    echo "Jenkins restarted successfully"
    break
  fi
  echo "Waiting for Jenkins after restart..."
  sleep 5
done

wget -O /tmp/jenkins-cli.jar http://127.0.0.1:8080/jnlpJars/jenkins-cli.jar

java -jar /tmp/jenkins-cli.jar -s http://127.0.0.1:8080 -auth admin:Admin@12345 install-plugin \
  git workflow-aggregator docker-workflow aws-credentials credentials-binding ws-cleanup pipeline-stage-view

java -jar /tmp/jenkins-cli.jar -s http://127.0.0.1:8080 -auth admin:Admin@12345 safe-restart

for i in {1..90}; do
  if curl -fsS http://127.0.0.1:8080/login >/dev/null; then
    echo "Jenkins available after plugin restart"
    break
  fi
  sleep 5
done

cd /home/ec2-user
rm -rf order-platform
git clone https://github.com/muhammadhassan120/order-platform.git
cd order-platform

SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id ${var.db_secret_arn} --region us-east-2 --query SecretString --output text)
DB_HOST=$(echo "$SECRET_JSON" | jq -r .host)
DB_PORT=$(echo "$SECRET_JSON" | jq -r .port)
DB_NAME=$(echo "$SECRET_JSON" | jq -r .dbname)
DB_USER=$(echo "$SECRET_JSON" | jq -r .username)
DB_PASS=$(echo "$SECRET_JSON" | jq -r .password)

until PGPASSWORD="$DB_PASS" psql "host=$DB_HOST port=$DB_PORT dbname=$DB_NAME user=$DB_USER sslmode=require" -c "SELECT 1" >/dev/null 2>&1; do
  echo "Waiting for DB..."
  sleep 10
done

PGPASSWORD="$DB_PASS" psql "host=$DB_HOST port=$DB_PORT dbname=$DB_NAME user=$DB_USER sslmode=require" -f scripts/seed-db.sql

cat > /tmp/job.xml <<'JOBXML'
<flow-definition plugin="workflow-job">
  <actions/>
  <description>Order Platform Pipeline</description>
  <keepDependencies>false</keepDependencies>
  <properties/>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>https://github.com/muhammadhassan120/order-platform.git</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="empty-list"/>
      <extensions/>
    </scm>
    <scriptPath>jenkins/Jenkinsfile</scriptPath>
    <lightweight>false</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
JOBXML

java -jar /tmp/jenkins-cli.jar -s http://127.0.0.1:8080 -auth admin:Admin@12345 create-job order-platform < /tmp/job.xml || true
java -jar /tmp/jenkins-cli.jar -s http://127.0.0.1:8080 -auth admin:Admin@12345 build order-platform || true

echo "===== JENKINS SETUP COMPLETED ====="
USERDATA

  tags = {
    Name = "${var.name_prefix}-jenkins"
  }
}