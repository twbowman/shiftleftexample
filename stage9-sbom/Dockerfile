FROM aquasec/trivy:latest AS trivy

FROM alpine:3.20

LABEL maintainer="stage9-sbom"
LABEL description="Stage 9: SBOM Generation & Image Signing"

ARG TARGETARCH
ARG COSIGN_VERSION=2.4.1

RUN apk add --no-cache bash jq docker-cli curl

# ── Corporate CA certificate (place your PEM in the build context) ───────────
COPY certs/corporate-ca.crt /usr/local/share/ca-certificates/corporate-ca.crt
RUN cat /usr/local/share/ca-certificates/corporate-ca.crt >> /etc/ssl/certs/ca-certificates.crt

# ── Trivy from official image ────────────────────────────────────────────────
COPY --from=trivy /usr/local/bin/trivy /usr/local/bin/trivy

# ── Cosign ───────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-${TARGETARCH}" \
    -o /usr/local/bin/cosign \
    && chmod +x /usr/local/bin/cosign

COPY stage9-sbom/sbom-sign.sh /usr/local/bin/sbom-sign.sh
RUN chmod +x /usr/local/bin/sbom-sign.sh

WORKDIR /workspace

ENTRYPOINT ["sbom-sign.sh"]
