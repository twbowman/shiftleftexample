FROM ubuntu:24.04

ARG TARGETARCH

LABEL maintainer="stage10-compliance"
LABEL description="Stage 10: Compliance & Policy Enforcement"

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

# ── Cosign ───────────────────────────────────────────────────────────────────
ARG COSIGN_VERSION=2.4.1
RUN curl -fsSL "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-${TARGETARCH}" \
    -o /usr/local/bin/cosign \
    && chmod +x /usr/local/bin/cosign

# ── Conftest ─────────────────────────────────────────────────────────────────
ARG CONFTEST_VERSION=0.56.0
RUN CONFTEST_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "x86_64") \
    && curl -fsSL "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_${CONFTEST_ARCH}.tar.gz" \
    -o /tmp/conftest.tar.gz \
    && tar -xzf /tmp/conftest.tar.gz -C /usr/local/bin conftest \
    && chmod +x /usr/local/bin/conftest \
    && rm /tmp/conftest.tar.gz

COPY comply.sh /usr/local/bin/comply.sh
RUN sed -i 's/\r$//' /usr/local/bin/comply.sh && chmod +x /usr/local/bin/comply.sh

WORKDIR /workspace

ENTRYPOINT ["comply.sh"]
