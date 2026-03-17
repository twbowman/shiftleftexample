FROM ubuntu:24.04

ARG TARGETARCH

LABEL maintainer="stage0-code"
LABEL description="Stage 0 Code: Code quality & general security"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# ── System packages ──────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    python3 \
    python3-pip \
    shellcheck \
    unzip \
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
ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# ── Python tools: ruff, bandit ───────────────────────────────────────────────
RUN pip3 install --no-cache-dir --break-system-packages \
    ruff \
    bandit

# ── hadolint ─────────────────────────────────────────────────────────────────
ARG HADOLINT_VERSION=2.14.0
RUN HADOLINT_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "x86_64") \
    && curl -fsSL "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-linux-${HADOLINT_ARCH}" \
    -o /usr/local/bin/hadolint \
    && chmod +x /usr/local/bin/hadolint

# ── gitleaks ─────────────────────────────────────────────────────────────────
ARG GITLEAKS_VERSION=8.21.2
RUN GITLEAKS_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "x64") \
    && curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz" \
    -o /tmp/gitleaks.tar.gz \
    && tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks \
    && chmod +x /usr/local/bin/gitleaks \
    && rm /tmp/gitleaks.tar.gz

COPY stage0-code/scan-code.sh /usr/local/bin/scan-code.sh
RUN sed -i 's/\r$//' /usr/local/bin/scan-code.sh && chmod +x /usr/local/bin/scan-code.sh

WORKDIR /workspace

ENTRYPOINT ["scan-code.sh"]
CMD ["--path", "/workspace"]
