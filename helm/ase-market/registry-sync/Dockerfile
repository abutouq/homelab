FROM alpine:3.20

RUN apk add --no-cache bash curl ca-certificates jq python3 py3-pip \
    && pip install --no-cache-dir --break-system-packages awscli \
    && curl -Ls "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
       -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl

COPY sync-registry-secret.sh /usr/local/bin/sync-registry-secret.sh
RUN chmod +x /usr/local/bin/sync-registry-secret.sh

ENTRYPOINT ["/usr/local/bin/sync-registry-secret.sh"]
