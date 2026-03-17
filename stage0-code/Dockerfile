FROM registry.access.redhat.com/ubi9/ubi:9.5

ARG TARGETARCH

LABEL maintainer="stage0-code"
LABEL description="Stage 0 Code: Code quality & general security"

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
    xz \
    && dnf clean all

# ── ShellCheck (binary — not available in UBI repos) ─────────────────────────
ARG SHELLCHECK_VERSION=0.10.0
RUN SC_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.${SC_ARCH}.tar.xz" \
    -o /tmp/shellcheck.tar.xz \
    && tar -xJf /tmp/shellcheck.tar.xz -C /tmp \
    && mv /tmp/shellcheck-v${SHELLCHECK_VERSION}/shellcheck /usr/local/bin/shellcheck \
    && chmod +x /usr/local/bin/shellcheck \
    && rm -rf /tmp/shellcheck*

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

# ── Python tools: ruff, bandit ───────────────────────────────────────────────
RUN pip3 install --no-cache-dir \
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

COPY scan-code.sh /usr/local/bin/scan-code.sh
RUN sed -i 's/\r$//' /usr/local/bin/scan-code.sh && chmod +x /usr/local/bin/scan-code.sh

WORKDIR /workspace

ENTRYPOINT ["scan-code.sh"]
CMD ["--path", "/workspace"]
