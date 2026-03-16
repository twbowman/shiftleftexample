FROM ubuntu:24.04

ARG TARGETARCH

LABEL maintainer="stage0-iac"
LABEL description="Stage 0 IaC: Infrastructure-as-code linting & compliance"

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
    unzip \
    && rm -rf /var/lib/apt/lists/*

# ── Corporate CA certificate (optional — empty placeholder used if not provided) ─
COPY certs/corporate-ca.crt /usr/local/share/ca-certificates/corporate-ca.crt
RUN if [ -s /usr/local/share/ca-certificates/corporate-ca.crt ]; then update-ca-certificates; fi
ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt
ENV REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# ── Python tools: checkov, ansible-lint ──────────────────────────────────────
RUN pip3 install --no-cache-dir --break-system-packages \
    checkov \
    ansible-lint

# ── tflint ───────────────────────────────────────────────────────────────────
ARG TFLINT_VERSION=0.53.0
RUN curl -fsSL "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${TARGETARCH}.zip" \
    -o /tmp/tflint.zip \
    && unzip /tmp/tflint.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/tflint \
    && rm /tmp/tflint.zip

COPY stage0-iac/scan-iac.sh /usr/local/bin/scan-iac.sh
RUN chmod +x /usr/local/bin/scan-iac.sh

WORKDIR /workspace

ENTRYPOINT ["scan-iac.sh"]
CMD ["--path", "/workspace"]
