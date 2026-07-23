#!/bin/bash
set -euo pipefail

# Pulls a {"username": "...", "password": "..."} JSON secret out of a
# LocalStack-backed Secrets Manager and materializes it as a native
# Kubernetes Secret. Idempotent (kubectl apply), safe to run on a schedule.
#
# Required env: LOCALSTACK_ENDPOINT, SECRET_ID, TARGET_SECRET_NAME, TARGET_NAMESPACE

secret_json=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region us-east-1 \
    secretsmanager get-secret-value --secret-id "$SECRET_ID" \
    --query SecretString --output text)

username=$(jq -r .username <<<"$secret_json")
password=$(jq -r .password <<<"$secret_json")

kubectl create secret generic "$TARGET_SECRET_NAME" \
    --namespace "$TARGET_NAMESPACE" \
    --from-literal=username="$username" \
    --from-literal=password="$password" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "synced $SECRET_ID -> secret/$TARGET_SECRET_NAME in $TARGET_NAMESPACE"
