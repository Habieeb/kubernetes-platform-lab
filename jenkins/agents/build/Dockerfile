FROM jenkins/inbound-agent:3391.va_37fa_a_305d6d-3-jdk21

USER root

ARG MAVEN_VERSION=3.9.16
ARG TRIVY_VERSION=0.72.0
ARG BUILDKIT_VERSION=0.33.1

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        skopeo \
        unzip && \
    rm -rf /var/lib/apt/lists/*


# Install Maven
RUN curl -fsSLo /tmp/maven.tar.gz \
    "https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" && \
    tar -xzf /tmp/maven.tar.gz -C /opt && \
    ln -s "/opt/apache-maven-${MAVEN_VERSION}/bin/mvn" /usr/local/bin/mvn && \
    rm /tmp/maven.tar.gz && \
    mvn --version

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


# Install BuildKit client
RUN curl -fsSLo /tmp/buildkit.tar.gz \
    "https://github.com/moby/buildkit/releases/download/v${BUILDKIT_VERSION}/buildkit-v${BUILDKIT_VERSION}.linux-amd64.tar.gz" && \
    tar -xzf /tmp/buildkit.tar.gz -C /usr/local bin/buildctl && \
    rm /tmp/buildkit.tar.gz && \
    buildctl --version

USER jenkins
