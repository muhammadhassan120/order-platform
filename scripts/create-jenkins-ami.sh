#!/bin/bash
set -euo pipefail

: "${INSTANCE_ID:?INSTANCE_ID is required}"
: "${AMI_NAME:=jenkins-golden-ami}"
: "${AWS_REGION:=us-east-2}"

echo "Creating AMI from instance ${INSTANCE_ID} in region ${AWS_REGION}"

AMI_ID=$(aws ec2 create-image \
  --region "${AWS_REGION}" \
  --instance-id "${INSTANCE_ID}" \
  --name "${AMI_NAME}-$(date +%Y%m%d-%H%M%S)" \
  --no-reboot \
  --query 'ImageId' \
  --output text)

echo "AMI creation started: ${AMI_ID}"
echo "You can check progress with:"
echo "aws ec2 describe-images --image-ids ${AMI_ID} --region ${AWS_REGION}"
