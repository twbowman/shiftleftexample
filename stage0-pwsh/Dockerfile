FROM ubuntu:24.04

ARG TARGETARCH
ARG POWERSHELL_VERSION=7.5.1

LABEL maintainer="stage0-pwsh"
LABEL description="Stage 0 PowerShell: PSScriptAnalyzer linting"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    jq \
    libicu74 \
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
