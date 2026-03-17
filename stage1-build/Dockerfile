FROM ubuntu:24.04

ARG TARGETARCH

LABEL maintainer="stage1-build"
LABEL description="Stage 1: Container image build"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# ── System packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# ── Corporate CA certificate (optional — filter out expired certs) ────────────
COPY certs/corporate-ca.crt /tmp/corporate-ca.crt
RUN if [ -s /tmp/corporate-ca.crt ]; then \
      csplit -z -f /tmp/cert- /tmp/corporate-ca.crt '/-----BEGIN CERTIFICATE-----/' '{*}' 2>/dev/null || true; \
      for f in /tmp/cert-*; do \
        if openssl x509 -in "$f" -checkend 0 -noout 2>/dev/null; then \
          cat "$f" >> /etc/ssl/certs/ca-certificates.crt; \
        fi; \
      done; \
      rm -f /tmp/cert-*; \
    fi \
    && rm -f /tmp/corporate-ca.crt
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# ── Docker CLI ───────────────────────────────────────────────────────────────
ARG DOCKER_VERSION=27.4.1
RUN DOCKER_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && curl -fsSL "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz" \
    -o /tmp/docker.tgz \
    && tar -xzf /tmp/docker.tgz --strip-components=1 -C /usr/local/bin docker/docker \
    && chmod +x /usr/local/bin/docker \
    && rm /tmp/docker.tgz

COPY build.sh /usr/local/bin/build.sh
RUN sed -i 's/\r$//' /usr/local/bin/build.sh && chmod +x /usr/local/bin/build.sh

WORKDIR /workspace

ENTRYPOINT ["build.sh"]
