FROM alpine:3.20

ARG TARGETARCH
ARG COSIGN_VERSION=2.4.1
ARG CONFTEST_VERSION=0.56.0

LABEL maintainer="stage10-compliance"
LABEL description="Stage 10: Compliance & Policy Enforcement"

RUN apk add --no-cache bash jq curl docker-cli

# ── Corporate CA certificate (place your PEM in the build context) ───────────
COPY corporate-ca.crt /usr/local/share/ca-certificates/corporate-ca.crt
RUN cat /usr/local/share/ca-certificates/corporate-ca.crt >> /etc/ssl/certs/ca-certificates.crt

# ── Cosign ───────────────────────────────────────────────────────────────────
RUN curl -fsSL "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-${TARGETARCH}" \
    -o /usr/local/bin/cosign \
    && chmod +x /usr/local/bin/cosign

# ── Conftest ─────────────────────────────────────────────────────────────────
RUN CONFTEST_ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "x86_64") \
    && curl -fsSL "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_${CONFTEST_ARCH}.tar.gz" \
    -o /tmp/conftest.tar.gz \
    && tar -xzf /tmp/conftest.tar.gz -C /usr/local/bin conftest \
    && chmod +x /usr/local/bin/conftest \
    && rm /tmp/conftest.tar.gz

COPY comply.sh /usr/local/bin/comply.sh
RUN chmod +x /usr/local/bin/comply.sh

WORKDIR /workspace

ENTRYPOINT ["comply.sh"]
