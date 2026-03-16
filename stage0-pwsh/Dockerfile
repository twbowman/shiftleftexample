FROM ubuntu:24.04

ARG TARGETARCH
ARG POWERSHELL_VERSION=7.5.1

LABEL maintainer="stage0-pwsh"
LABEL description="Stage 0 PowerShell: PSScriptAnalyzer linting"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

# ── Corporate CA certificate (place your PEM in the build context) ───────────
COPY corporate-ca.crt /usr/local/share/ca-certificates/corporate-ca.crt
RUN update-ca-certificates

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    jq \
    libicu74 \
    && rm -rf /var/lib/apt/lists/*

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
RUN chmod +x /usr/local/bin/scan-pwsh.sh

WORKDIR /workspace

ENTRYPOINT ["scan-pwsh.sh"]
CMD ["--path", "/workspace"]
