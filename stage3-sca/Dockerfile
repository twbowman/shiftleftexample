FROM aquasec/trivy:latest

LABEL maintainer="stage3-sca"
LABEL description="Stage 3: Software Composition Analysis with Trivy"

USER root

# ── Corporate CA certificate (place your PEM in the build context) ───────────
COPY certs/corporate-ca.crt /usr/local/share/ca-certificates/corporate-ca.crt
RUN cat /usr/local/share/ca-certificates/corporate-ca.crt >> /etc/ssl/certs/ca-certificates.crt

RUN apk add --no-cache bash jq docker-cli

COPY stage3-sca/scan.sh /usr/local/bin/scan.sh
RUN chmod +x /usr/local/bin/scan.sh

WORKDIR /workspace

ENTRYPOINT ["scan.sh"]
