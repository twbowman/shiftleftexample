# Sample Dockerfile with intentional hadolint issues

# hadolint: DL3007 - using latest tag
FROM ubuntu:latest

# hadolint: DL3008 - not pinning apt package versions
# hadolint: DL3009 - not cleaning up apt cache
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    python3

# hadolint: DL3003 - using cd instead of WORKDIR
RUN cd /opt && mkdir myapp

# hadolint: DL4006 - pipe without pipefail
RUN curl -s https://example.com/setup.sh | bash

# hadolint: DL3020 - use COPY instead of ADD for files
ADD app.tar.gz /opt/myapp/

# hadolint: SC2086 - double quote to prevent globbing
ARG APP_VERSION
RUN echo $APP_VERSION > /opt/myapp/version.txt

WORKDIR /opt/myapp

# hadolint: DL3025 - use JSON notation for CMD
CMD python3 app.py

EXPOSE 8080
