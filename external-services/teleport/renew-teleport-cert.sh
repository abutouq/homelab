#!/bin/bash
set -euo pipefail

export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
token=$(aws --endpoint-url="http://secrets-manager.homebytes.space:4566" --region us-east-1 \
  secretsmanager get-secret-value --secret-id "cloudflare-api-token" --query SecretString --output text)

creds_file=$(mktemp)
trap 'rm -f "$creds_file"' EXIT
printf 'dns_cloudflare_api_token = %s\n' "$token" > "$creds_file"
chmod 600 "$creds_file"

certbot certonly \
  --non-interactive \
  --agree-tos \
  --register-unsafely-without-email \
  --dns-cloudflare \
  --dns-cloudflare-credentials "$creds_file" \
  --dns-cloudflare-propagation-seconds 30 \
  -d "*.teleport.homebytes.space" -d "teleport.homebytes.space"


cp /etc/letsencrypt/live/teleport.homebytes.space/fullchain.pem /home/ubuntu/teleport-tls/teleport.homebytes.space.pem
cp /etc/letsencrypt/live/teleport.homebytes.space/privkey.pem /home/ubuntu/teleport-tls/teleport.homebytes.space.key

chown ubuntu:ubuntu /home/ubuntu/teleport-tls/teleport.homebytes.space.pem
chown ubuntu:ubuntu /home/ubuntu/teleport-tls/teleport.homebytes.space.key

service teleport restart