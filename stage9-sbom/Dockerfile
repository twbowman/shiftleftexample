FROM ubuntu:24.04

ARG TARGETARCH

LABEL maintainer="stage9-sbom"
LABEL description="Stage 9: SBOM Generation & Image Signing"

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
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# ── Docker CLI ───────────────────────────────────────────────────────────────
ARG DOCKER_VERSION=27.4.1
RUN DOCKER_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "aarch64" || echo "x86_64") \
    && curl -fsSL "https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz" \
    -o /tmp/docker.tgz \
    && tar -xzf /tmp/docker.tgz --strip-components=1 -C /usr/local/bin docker/docker \
    && chmod +x /usr/local/bin/docker \
    && rm /tmp/docker.tgz

# ── Trivy ────────────────────────────────────────────────────────────────────
ARG TRIVY_VERSION=0.69.3
RUN TRIVY_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "ARM64" || echo "64bit") \
    && curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz" \
    -o /tmp/trivy.tar.gz \
    && tar -xzf /tmp/trivy.tar.gz -C /usr/local/bin trivy \
    && chmod +x /usr/local/bin/trivy \
    && rm /tmp/trivy.tar.gz

# ── Cosign ───────────────────────────────────────────────────────────────────
ARG COSIGN_VERSION=2.4.1
RUN curl -fsSL "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-${TARGETARCH}" \
    -o /usr/local/bin/cosign \
    && chmod +x /usr/local/bin/cosign

COPY stage9-sbom/sbom-sign.sh /usr/local/bin/sbom-sign.sh
RUN chmod +x /usr/local/bin/sbom-sign.sh

WORKDIR /workspace

ENTRYPOINT ["sbom-sign.sh"]
