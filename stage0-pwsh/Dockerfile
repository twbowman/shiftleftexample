FROM registry.access.redhat.com/ubi9/ubi-minimal:9.5

ARG TARGETARCH
ARG POWERSHELL_VERSION=7.5.1

LABEL maintainer="stage0-pwsh"
LABEL description="Stage 0 PowerShell: PSScriptAnalyzer linting"

ENV LANG=C.UTF-8

RUN microdnf install -y --nodocs \
    bash \
    ca-certificates \
    jq \
    libicu \
    openssl \
    tar \
    gzip \
    && microdnf clean all

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
ENV SSL_CERT_FILE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
ENV CURL_CA_BUNDLE=/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem

# ── PowerShell Core + PSScriptAnalyzer ───────────────────────────────────────
RUN PS_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "x64") \
    && curl -fsSL "https://github.com/PowerShell/PowerShell/releases/download/v${POWERSHELL_VERSION}/powershell-${POWERSHELL_VERSION}-linux-${PS_ARCH}.tar.gz" \
    -o /tmp/powershell.tar.gz \
    && mkdir -p /opt/microsoft/powershell/7 \
    && tar -xzf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7 \
    && chmod +x /opt/microsoft/powershell/7/pwsh \
    && ln -s /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh \
    && rm /tmp/powershell.tar.gz \
    && pwsh -NoProfile -NonInteractive -Command "Install-Module -Name PSScriptAnalyzer -Scope AllUsers -Force -SkipPublisherCheck"

COPY scan-pwsh.sh /usr/local/bin/scan-pwsh.sh
RUN sed -i 's/\r$//' /usr/local/bin/scan-pwsh.sh && chmod +x /usr/local/bin/scan-pwsh.sh

WORKDIR /workspace

ENTRYPOINT ["scan-pwsh.sh"]
CMD ["--path", "/workspace"]
