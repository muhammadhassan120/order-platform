#!/bin/bash
set -euo pipefail

PREVIOUS_TAG="${1:-}"

if [ -z "${PREVIOUS_TAG}" ]; then
  echo "Usage: ./rollback.sh <previous-image-tag>"
  echo "Recent tags:"
  aws ecr describe-images \
    --repository-name order-platform-repo \
    --query 'imageDetails | sort_by(@, &imagePushedAt) | [-5:].imageTags[0]' \
    --output table
  exit 1
fi

: "${AWS_REGION:=us-east-2}"
: "${ECR_REPO:=992382749898.dkr.ecr.us-east-2.amazonaws.com/order-platform-repo}"
: "${ECS_CLUSTER:=order-platform-cluster}"
: "${ECS_SERVICE:=order-platform-service}"
: "${TASK_CONTAINER:=order-api}"

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
