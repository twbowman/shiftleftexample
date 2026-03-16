FROM aquasec/trivy:latest

LABEL maintainer="stage3-sca"
LABEL description="Stage 3: Software Composition Analysis with Trivy"

USER root

RUN apk add --no-cache bash jq docker-cli

COPY scan.sh /usr/local/bin/scan.sh
RUN chmod +x /usr/local/bin/scan.sh

WORKDIR /workspace

ENTRYPOINT ["scan.sh"]
