FROM registry.access.redhat.com/ubi9/ubi:9.5

ARG TARGETARCH

LABEL maintainer="stage0-iac"
LABEL description="Stage 0 IaC: Infrastructure-as-code linting & compliance"

ENV LANG=C.UTF-8

# ── System packages ──────────────────────────────────────────────────────────
RUN dnf install -y --nodocs --allowerasing \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    openssl \
    python3 \
    python3-pip \
    unzip \
    && dnf clean all

# ── Corporate CA certificate (optional — filter out expired certs) ────────────
COPY certs/corporate-ca.crt /tmp/corporate-ca.crt
RUN if [ -s /tmp/corporate-ca.crt ]; then \
      csplit -z -f /tmp/cert- /tmp/corporate-ca.crt '/-----BEGIN CERTIFICATE-----/' '{*}' 2>/dev/null || true; \
      for f in /tmp/cert-*; do \
        if openssl x509 -in "$f" -checkend 0 -noout 2>/dev/null; then \
          cat "$f" >> /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem; \
        fi; \
      done; \
      rm -f /tmp/cert-*; \
    fi \
    && rm -f /tmp/corporate-ca.crt
ENV PIP_CERT=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
ENV REQUESTS_CA_BUNDLE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
ENV SSL_CERT_FILE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
ENV CURL_CA_BUNDLE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem

# ── Python tools: checkov, ansible-lint ──────────────────────────────────────
RUN pip3 install --no-cache-dir \
    checkov \
    ansible-lint

# ── tflint ───────────────────────────────────────────────────────────────────
ARG TFLINT_VERSION=0.53.0
RUN curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${TARGETARCH}.zip" \
    -o /tmp/tflint.zip \
    && unzip /tmp/tflint.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/tflint \
    && rm /tmp/tflint.zip

COPY scan-iac.sh /usr/local/bin/scan-iac.sh
RUN sed -i 's/\r$//' /usr/local/bin/scan-iac.sh && chmod +x /usr/local/bin/scan-iac.sh

WORKDIR /workspace

ENTRYPOINT ["scan-iac.sh"]
CMD ["--path", "/workspace"]
