FROM ubuntu:24.04

ARG TARGETARCH

LABEL maintainer="stage0-code"
LABEL description="Stage 0 Code: Code quality & general security"

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
    shellcheck \
    unzip \
    && rm -rf /var/lib/apt/lists/*

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
RUN curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${TARGETARCH}.tar.gz" \
    -o /tmp/gitleaks.tar.gz \
    && tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks \
    && chmod +x /usr/local/bin/gitleaks \
    && rm /tmp/gitleaks.tar.gz

COPY scan-code.sh /usr/local/bin/scan-code.sh
RUN chmod +x /usr/local/bin/scan-code.sh

WORKDIR /workspace

ENTRYPOINT ["scan-code.sh"]
CMD ["--path", "/workspace"]
