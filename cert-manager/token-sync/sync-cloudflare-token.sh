#!/bin/bash
set -euo pipefail

# Pulls the Cloudflare API token (a plain-string secret, not JSON) out of a
# LocalStack-backed Secrets Manager and materializes it as a native
# Kubernetes Secret for cert-manager's ClusterIssuer to reference. Idempotent
# (kubectl apply), safe to run on a schedule.
#
# Required env: LOCALSTACK_ENDPOINT, SECRET_ID, TARGET_SECRET_NAME, TARGET_NAMESPACE, SECRET_KEY

token=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" --region us-east-1 \
    secretsmanager get-secret-value --secret-id "$SECRET_ID" \
    --query SecretString --output text)

kubectl create secret generic "$TARGET_SECRET_NAME" \
    --namespace "$TARGET_NAMESPACE" \
    --from-literal="${SECRET_KEY}=${token}" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "synced $SECRET_ID -> secret/$TARGET_SECRET_NAME in $TARGET_NAMESPACE"
