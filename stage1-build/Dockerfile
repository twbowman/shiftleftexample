FROM docker:27-cli

LABEL maintainer="stage1-build"
LABEL description="Stage 1: Container image build"

RUN apk add --no-cache bash jq

COPY build.sh /usr/local/bin/build.sh
RUN chmod +x /usr/local/bin/build.sh

WORKDIR /workspace

ENTRYPOINT ["build.sh"]
