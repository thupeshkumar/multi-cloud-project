FROM jenkins/jenkins:lts-jdk21
USER root
ARG TERRAFORM_VERSION=1.13.5
ARG TARGETARCH=amd64
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl unzip git openssh-client shellcheck \
    && rm -rf /var/lib/apt/lists/*
RUN set -eux; \
    cd /tmp; \
    curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip"; \
    curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"; \
    grep " terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip$" "terraform_${TERRAFORM_VERSION}_SHA256SUMS" | sha256sum -c -; \
    unzip "terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" -d /usr/local/bin; \
    rm "terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" "terraform_${TERRAFORM_VERSION}_SHA256SUMS"
USER jenkins
RUN jenkins-plugin-cli --plugins workflow-aggregator git credentials-binding ssh-agent
