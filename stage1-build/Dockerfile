FROM docker:27-cli

LABEL maintainer="stage1-build"
LABEL description="Stage 1: Container image build"

# ── Corporate CA certificate (place your PEM in the build context) ───────────
COPY corporate-ca.crt /usr/local/share/ca-certificates/corporate-ca.crt
RUN cat /usr/local/share/ca-certificates/corporate-ca.crt >> /etc/ssl/certs/ca-certificates.crt

RUN apk add --no-cache bash jq

COPY build.sh /usr/local/bin/build.sh
RUN chmod +x /usr/local/bin/build.sh

WORKDIR /workspace

ENTRYPOINT ["build.sh"]
