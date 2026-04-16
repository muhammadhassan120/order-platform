#!/bin/bash
set -euo pipefail

: "${AWS_REGION:?AWS_REGION is required}"
: "${ECR_REPO:?ECR_REPO is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${ECS_CLUSTER:?ECS_CLUSTER is required}"
: "${ECS_SERVICE:?ECS_SERVICE is required}"
: "${TASK_CONTAINER:=order-api}"

IMAGE_URI="${ECR_REPO}:${IMAGE_TAG}"

echo "Deploying image ${IMAGE_URI} to ECS service ${ECS_SERVICE} in cluster ${ECS_CLUSTER}"

CURRENT_TASK_DEF_ARN=$(aws ecs describe-services \
  --region "${AWS_REGION}" \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --query 'services[0].taskDefinition' \
  --output text)

echo "Current task definition: ${CURRENT_TASK_DEF_ARN}"

TASK_DEF_JSON=$(aws ecs describe-task-definition \
  --region "${AWS_REGION}" \
  --task-definition "${CURRENT_TASK_DEF_ARN}" \
  --query 'taskDefinition' \
  --output json)

NEW_TASK_DEF_JSON=$(echo "${TASK_DEF_JSON}" | jq \
  --arg IMAGE_URI "${IMAGE_URI}" \
  --arg TASK_CONTAINER "${TASK_CONTAINER}" \
  '
  del(
    .taskDefinitionArn,
    .revision,
    .status,
    .requiresAttributes,
    .compatibilities,
    .registeredAt,
    .registeredBy
  )
  | .containerDefinitions |= map(
      if .name == $TASK_CONTAINER
      then .image = $IMAGE_URI
      else .
      end
    )
  ')

NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --region "${AWS_REGION}" \
  --cli-input-json "${NEW_TASK_DEF_JSON}" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)

echo "Registered new task definition: ${NEW_TASK_DEF_ARN}"

aws ecs update-service \
  --region "${AWS_REGION}" \
  --cluster "${ECS_CLUSTER}" \
  --service "${ECS_SERVICE}" \
  --task-definition "${NEW_TASK_DEF_ARN}" \
  --force-new-deployment >/dev/null

echo "Waiting for service to become stable..."
if ! aws ecs wait services-stable \
  --region "${AWS_REGION}" \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}"; then

  echo "Service failed to stabilize. Showing service events:"
  aws ecs describe-services \
    --region "${AWS_REGION}" \
    --cluster "${ECS_CLUSTER}" \
    --services "${ECS_SERVICE}" \
    --query 'services[0].events[0:10].[createdAt,message]' \
    --output table || true

  echo "Showing stopped tasks:"
  TASK_ARNS=$(aws ecs list-tasks \
    --region "${AWS_REGION}" \
    --cluster "${ECS_CLUSTER}" \
    --service-name "${ECS_SERVICE}" \
    --desired-status STOPPED \
    --query 'taskArns' \
    --output text || true)

  if [ -n "${TASK_ARNS:-}" ] && [ "${TASK_ARNS}" != "None" ]; then
    aws ecs describe-tasks \
      --region "${AWS_REGION}" \
      --cluster "${ECS_CLUSTER}" \
      --tasks ${TASK_ARNS} \
      --query 'tasks[*].[taskArn,lastStatus,stopCode,stoppedReason,containers[*].reason]' \
      --output table || true
  fi

  exit 1
fi

echo "Deployment finished successfully."