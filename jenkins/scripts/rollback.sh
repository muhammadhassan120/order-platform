#!/bin/bash
set -euo pipefail

PREVIOUS_TAG="${1:-}"

: "${AWS_REGION:=us-east-2}"
: "${ECR_REPOSITORY:=order-platform-repo}"
: "${ECS_CLUSTER:=order-platform-cluster}"
: "${ECS_SERVICE:=order-platform-service}"
: "${TASK_CONTAINER:=order-api}"

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
ECR_REPO="${ECR_REPO:-${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}}"

if [ -z "${PREVIOUS_TAG}" ]; then
  echo "Usage: ./rollback.sh <previous-image-tag>"
  echo "Recent tags:"
  aws ecr describe-images \
    --region "${AWS_REGION}" \
    --repository-name "${ECR_REPOSITORY}" \
    --query 'imageDetails | sort_by(@, &imagePushedAt) | [-5:].imageTags[0]' \
    --output table
  exit 1
fi

echo "Rolling back to image tag: ${PREVIOUS_TAG}"

CURRENT_TASK_DEF_ARN=$(aws ecs describe-services \
  --region "${AWS_REGION}" \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --query 'services[0].taskDefinition' \
  --output text)

TASK_DEF=$(aws ecs describe-task-definition \
  --region "${AWS_REGION}" \
  --task-definition "${CURRENT_TASK_DEF_ARN}" \
  --query 'taskDefinition' \
  --output json)

NEW_TASK_DEF=$(echo "${TASK_DEF}" | jq \
  --arg IMG "${ECR_REPO}:${PREVIOUS_TAG}" \
  --arg CONTAINER "${TASK_CONTAINER}" \
  '
  .containerDefinitions = (
    .containerDefinitions
    | map(if .name == $CONTAINER then .image = $IMG else . end)
  )
  | del(
      .taskDefinitionArn,
      .revision,
      .status,
      .requiresAttributes,
      .compatibilities,
      .registeredAt,
      .registeredBy
    )
  ')

NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --region "${AWS_REGION}" \
  --cli-input-json "${NEW_TASK_DEF}" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

aws ecs update-service \
  --region "${AWS_REGION}" \
  --cluster "${ECS_CLUSTER}" \
  --service "${ECS_SERVICE}" \
  --task-definition "${NEW_TASK_DEF_ARN}" \
  --force-new-deployment

echo "Rollback initiated."
