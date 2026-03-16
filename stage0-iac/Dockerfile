FROM ubuntu:24.04

ARG TARGETARCH

LABEL maintainer="stage0-iac"
LABEL description="Stage 0 IaC: Infrastructure-as-code linting & compliance"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# ── Corporate CA certificate (place your PEM in the build context) ───────────
COPY corporate-ca.crt /usr/local/share/ca-certificates/corporate-ca.crt
RUN update-ca-certificates
ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt

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

COPY scan-iac.sh /usr/local/bin/scan-iac.sh
RUN chmod +x /usr/local/bin/scan-iac.sh

WORKDIR /workspace

ENTRYPOINT ["scan-iac.sh"]
CMD ["--path", "/workspace"]
