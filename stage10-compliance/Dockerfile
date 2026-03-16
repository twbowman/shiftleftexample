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

# ── Corporate CA certificate (optional — empty placeholder used if not provided) ─
COPY certs/corporate-ca.crt /usr/local/share/ca-certificates/corporate-ca.crt
RUN if [ -s /usr/local/share/ca-certificates/corporate-ca.crt ]; then update-ca-certificates; fi

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

COPY stage10-compliance/comply.sh /usr/local/bin/comply.sh
RUN chmod +x /usr/local/bin/comply.sh

WORKDIR /workspace

ENTRYPOINT ["comply.sh"]
