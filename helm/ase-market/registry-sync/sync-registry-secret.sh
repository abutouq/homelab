#!/bin/bash
set -euo pipefail

# Pulls a Docker registry auth config (a plain-string secret holding the full
# .dockerconfigjson blob, not JSON keys to fan out) out of a LocalStack-backed
# Secrets Manager and materializes it as a native
# kubernetes.io/dockerconfigjson Secret, ready for use in imagePullSecrets.
# Idempotent (kubectl apply), safe to run on a schedule.
#
# Required env: LOCALSTACK_ENDPOINT, SECRET_ID, TARGET_SECRET_NAME, TARGET_NAMESPACE

dockerconfigjson=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region us-east-1 \
    secretsmanager get-secret-value --secret-id "$SECRET_ID" \
    --query SecretString --output text)

kubectl create secret generic "$TARGET_SECRET_NAME" \
    --namespace "$TARGET_NAMESPACE" \
    --type=kubernetes.io/dockerconfigjson \
    --from-literal=.dockerconfigjson="$dockerconfigjson" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "synced $SECRET_ID -> secret/$TARGET_SECRET_NAME in $TARGET_NAMESPACE"
