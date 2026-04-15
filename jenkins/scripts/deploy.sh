#!/bin/bash
set -euo pipefail

: "${AWS_REGION:?AWS_REGION is required}"
: "${ECR_REPO:?ECR_REPO is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${ECS_CLUSTER:?ECS_CLUSTER is required}"
: "${ECS_SERVICE:?ECS_SERVICE is required}"
: "${TASK_CONTAINER:=order-api}"

echo "Deploying image ${ECR_REPO}:${IMAGE_TAG} to ECS service ${ECS_SERVICE} in cluster ${ECS_CLUSTER}"

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
  --arg IMG "${ECR_REPO}:${IMAGE_TAG}" \
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

echo "Deployment started successfully."
