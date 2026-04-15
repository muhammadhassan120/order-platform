#!/bin/bash
set -euo pipefail

: "${AWS_REGION:?AWS_REGION is required}"
: "${ECS_CLUSTER:?ECS_CLUSTER is required}"
: "${ECS_SERVICE:?ECS_SERVICE is required}"

ALB_DNS=$(aws ecs describe-services \
  --region "${AWS_REGION}" \
  --cluster "${ECS_CLUSTER}" \
  --services "${ECS_SERVICE}" \
  --query 'services[0].loadBalancers[0].targetGroupArn' \
  --output text | \
xargs -I {} aws elbv2 describe-target-groups \
  --region "${AWS_REGION}" \
  --target-group-arns {} \
  --query 'TargetGroups[0].LoadBalancerArns[0]' \
  --output text | \
xargs -I {} aws elbv2 describe-load-balancers \
  --region "${AWS_REGION}" \
  --load-balancer-arns {} \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "Testing against ALB: http://${ALB_DNS}"

echo "Test 1: Health check"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${ALB_DNS}/health")

if [ "${HTTP_CODE}" != "200" ]; then
  echo "FAIL: Health check returned HTTP ${HTTP_CODE}"
  exit 1
fi

echo "PASS: Health check returned 200"

echo "Test 2: Create order"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "http://${ALB_DNS}/orders" \
  -H "Content-Type: application/json" \
  -d '{
    "customer_email": "smoke-test@internal.dev",
    "items": [{"product_id": "SMOKE-001", "qty": 1}]
  }')

BODY=$(echo "${RESPONSE}" | head -n 1)
HTTP_CODE=$(echo "${RESPONSE}" | tail -n 1)

if [ "${HTTP_CODE}" != "201" ] && [ "${HTTP_CODE}" != "409" ]; then
  echo "FAIL: Create order returned HTTP ${HTTP_CODE}"
  echo "Body: ${BODY}"
  exit 1
fi

echo "PASS: Create order returned ${HTTP_CODE}"
echo "All smoke tests passed."
