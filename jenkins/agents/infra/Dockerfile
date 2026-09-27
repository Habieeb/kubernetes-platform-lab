FROM jenkins/inbound-agent:latest-jdk21

USER root

ARG TERRAFORM_VERSION=1.14.6
ARG PACKER_VERSION=1.14.3
ARG TRIVY_VERSION=0.72.0

RUN apt-get update && \
    apt-get install -y \
        curl \
        unzip \
        gnupg \
        lsb-release \
        ca-certificates \
        git \
        python3 && \
    python3 --version && \
    rm -rf /var/lib/apt/lists/*

# Install Terraform
RUN curl -fsSLo /tmp/terraform.zip \
    "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" && \
    unzip -j /tmp/terraform.zip terraform -d /usr/local/bin && \
    rm /tmp/terraform.zip && \
    terraform version

# Install Packer
RUN curl -fsSLo /tmp/packer.zip \
    "https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip" && \
    unzip -j /tmp/packer.zip packer -d /usr/local/bin && \
    rm /tmp/packer.zip && \
    packer version

# Install Trivy
RUN curl -fsSLo /tmp/trivy.deb \
    "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.deb" && \
    dpkg -i /tmp/trivy.deb && \
    rm /tmp/trivy.deb && \
    trivy --version

# Install AWS CLI v2
RUN curl -fsSLo /tmp/awscliv2.zip \
    "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/aws /tmp/awscliv2.zip && \
    aws --version

USER jenkins
