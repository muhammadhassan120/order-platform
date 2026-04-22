BEFORE TERRAFORM APPLY 


1) go to aws console --> ec2 -->  key pairs section --> create key pair 
named "order-platform-key.pem"


2) go to infra/security.tf --> update admin cidr with your actual ip addresss.

3) go to infra.db-seed.tf , in the end add your key pair location in your pc in this block
private_key = file("D:/key-pairs/order-platform-key.pem")

on line 25

4) go to infra/environments/dev.tfvars , replace with your email.

5) create s3 bucket for terraform tfstate files , then go to 'infra/versions.tf' --->
replace with your with your bucket name 

RUN  terraform apply --auto-approve

------------------------------------------------

6) go to jenkins/scripts/rollback.sh in line 17 
SOMETHING LIKE THIS :
: "${ECR_REPO:=992382749898.dkr.ecr.us-east-2.amazonaws.com/order-platform-repo}"
 
 kepp remain same just paste your aws account id 
 : "${ECR_REPO:=YOUR-ACCOUNT-ID-AWS.dkr.ecr.us-east-2.amazonaws.com/order-platform-repo}"


 7) go to jenkins/Jenkinsfile in line 6 something like this :
   environment {
    AWS_REGION     = 'us-east-2'
    ECR_REPO       = '992382749898.dkr.ecr.us-east-2.amazonaws.com/order-platform-repo'
    ECS_CLUSTER    = 'order-platform-cluster'
    ECS_SERVICE    = 'order-platform-service'
    TASK_CONTAINER = 'order-api'
  }


only replace numbers with your actual aws account id 
ECR_REPO       = 'YOUR-ACCOUNT-ID.dkr.ecr.us-east-2.amazonaws.com/order-platform-repo'

8) go to root folder "/order-processing"
git init 
then git add .
and push to github 


open jenkins instance ip address