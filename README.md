# Kubernetes Platform Lab

A production-style DevOps platform built around **AWS EKS, Terraform, Jenkins, Packer, Karpenter, Helm, Argo CD, SonarQube, BuildKit, Trivy, Amazon ECR, and GitHub**.

The project demonstrates how infrastructure provisioning, application CI, security scanning, immutable artifact publication, GitOps deployment, and Kubernetes capacity management can be separated into clearly defined responsibilities.

> **Project goal:** build the platform as an engineering system rather than a collection of disconnected DevOps tools.

---

## Architecture

```text
                         Developer
                             |
                         git push
                             |
                             v
                          GitHub
                             |
                    webhook / SCM event
                             |
                             v
                    +------------------+
                    |     Jenkins      |
                    |    Controller    |
                    +------------------+
                             |
             +---------------+---------------+
             |                               |
             v                               v
     +---------------+               +---------------+
     |  infra-agent  |               |  build-agent  |
     +---------------+               +---------------+
     | Terraform     |               | Java 21       |
     | Packer        |               | Maven         |
     | Trivy IaC     |               | SonarScanner  |
     | AWS CLI       |               | BuildKit CLI  |
     | Git           |               | Trivy         |
     +---------------+               | Skopeo        |
             |                       | AWS CLI       |
             |                       +---------------+
             |                               |
             v                               v
     +------------------------------------------------+
     |                      AWS                       |
     |                                                |
     |  VPC       IAM        EKS        ECR           |
     |   |                     |          ^            |
     |   |                     |          |            |
     |   |                     |    immutable image    |
     |   |                     |          |            |
     +---|---------------------|----------|------------+
                                      
                                       CI
                                        |
                         Test -> SonarQube
                                        |
                              Quality Gate
                                        |
                                   BuildKit
                                        |
                                      Trivy
                                        |
                                      Skopeo
                                        |
                                        v
                                Amazon ECR
                                        |
                             GitOps image update
                                        |
                                        v
                                      Git
                                        |
                                        v
                                   Argo CD
                                        |
                              Helm reconciliation
                                        |
                                        v
                                      EKS
                                        |
                              +---------+---------+
                              |                   |
                              v                   v
                          Workloads           Karpenter
                                                  |
                                           Dynamic EC2
                                             capacity
```

---

# Key Design Principle

The platform deliberately separates **CI from CD**.

### Jenkins owns CI

Jenkins is responsible for:

```text
Source checkout
      |
      v
Application tests
      |
      v
SonarQube analysis
      |
      v
Quality Gate
      |
      v
Container build
      |
      v
Trivy security scan
      |
      v
Publish approved artifact to ECR
      |
      v
Update GitOps desired state
```

### Argo CD owns CD

Argo CD is responsible for:

```text
Git desired state
      |
      v
Compare desired vs live state
      |
      v
Render Helm chart
      |
      v
Reconcile Kubernetes resources
      |
      v
Maintain desired state
```

Jenkins therefore does **not** perform routine application deployments with:

```bash
kubectl set image
kubectl apply
helm upgrade
```

Instead:

```text
Jenkins
   |
   v
Git desired-state update
   |
   v
Argo CD
   |
   v
Kubernetes
```

This keeps Git as the deployment source of truth.

---

# Technology Stack

| Area | Technology |
|---|---|
| Cloud | AWS |
| Kubernetes | Amazon EKS |
| Infrastructure as Code | Terraform |
| Machine Images | Packer |
| CI | Jenkins |
| Git Hosting | GitHub |
| GitOps / CD | Argo CD |
| Kubernetes Packaging | Helm |
| Node Autoscaling | Karpenter |
| Application | Java 21 / Spring Boot |
| Build | Maven |
| Code Quality | SonarQube |
| Container Build | BuildKit |
| Container Security | Trivy |
| Image Promotion | Skopeo |
| Container Registry | Amazon ECR |
| Jenkins Runtime | Dedicated Docker agents |
| AWS CLI | AWS CLI v2 |

---

# Repository Structure

```text
kubernetes-platform-lab/
│
├── Jenkinsfile
├── Jenkinsfile.app
│
├── backend/
│   ├── pom.xml
│   ├── Dockerfile
│   └── src/
│
├── terraform/
│   ├── versions.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── network.tf
│   ├── eks.tf
│   ├── ecr.tf
│   ├── karpenter.tf
│   ├── outputs.tf
│   └── .terraform.lock.hcl
│
├── packer/
│   └── eks-node.pkr.hcl
│
├── jenkins/
│   └── agents/
│       ├── infra/
│       │   └── Dockerfile
│       ├── build/
│       │   └── Dockerfile
│       └── kubernetes/
│           └── Dockerfile
│
├── helm/
│   └── platform/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│
├── argocd/
│   └── applications/
│       └── platform.yaml
│
├── kubernetes/
│   └── karpenter/
│       ├── ec2nodeclass.yaml
│       └── nodepool.yaml
│
└── clusters/
```

---

# Jenkins Architecture

The Jenkins controller is used for **orchestration only**.

Pipeline workloads execute on dedicated agents rather than the controller.

## Infrastructure Agent

The `infra-agent` contains the tooling required for infrastructure pipelines:

```text
Terraform 1.14.6
Packer 1.14.3
Trivy 0.72.0
AWS CLI v2
Git
Java 21
```

Responsibilities include:

```text
Terraform validation
Terraform planning
Terraform apply
Trivy IaC scanning
Packer AMI creation
AWS infrastructure operations
```

The agent connects to Jenkins using Jenkins Remoting over WebSocket.

---

## Build Agent

Application CI runs on a separate `build-agent`.

Its toolchain includes:

```text
Java 21
Maven
Git
AWS CLI v2
Trivy
BuildKit client
Skopeo
```

This separation prevents application builds from sharing the infrastructure execution environment.

---

# Application CI Pipeline

The application pipeline follows this sequence:

```text
Checkout
   |
   v
Unit Tests
   |
   v
SonarQube Analysis
   |
   v
Quality Gate
   |
   v
Build Container
   |
   v
Trivy Image Scan
   |
   v
Publish to ECR
   |
   v
GitOps Promotion
```

The important security property is:

> The image that passes the security gate is the image that is promoted.

The container is built once as an OCI artifact using BuildKit.

---

# SonarQube Quality Gate

SonarQube runs separately from the Jenkins build agent.

```text
Jenkins build-agent
       |
       | SonarScanner
       v
   SonarQube
       |
       | webhook
       v
    Jenkins
       |
       v
 Quality Gate
```

Jenkins waits for the Quality Gate before container promotion can continue.

A failed Quality Gate prevents the image from moving into the release path.

---

# Container Build Strategy

The project intentionally avoids mounting:

```text
/var/run/docker.sock
```

into the Jenkins build agent.

Instead, container builds use **BuildKit**.

```text
Jenkins build-agent
       |
       | BuildKit client
       v
BuildKit service
       |
       v
OCI image archive
```

This avoids granting the Jenkins build container direct control over the host Docker daemon.

---

# Container Security

The generated application image is scanned using Trivy before publication.

The release gate blocks:

```text
HIGH
CRITICAL
```

vulnerabilities.

Conceptually:

```bash
trivy image \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  <approved-image>
```

A vulnerable image therefore cannot continue through the normal promotion path.

---

# Immutable Artifact Promotion

The application image is built **once**.

The approved OCI artifact is then copied to Amazon ECR using Skopeo.

```text
BuildKit
   |
   v
OCI archive
   |
   v
Trivy
   |
   | PASS
   v
Skopeo
   |
   v
Amazon ECR
```

This avoids rebuilding the container between scanning and publication.

---

# Amazon ECR

Application images are stored in:

```text
platform-lab-app
```

The repository uses immutable tags.

The successfully promoted backend image is:

```text
420796370564.dkr.ecr.eu-west-1.amazonaws.com/platform-lab-app:73f0a82aa647063cb18397fb6a0a47b7aecf85b8
```

The approved digest recorded during the pipeline is:

```text
sha256:e89ead008799d906de1764ab0834e1f9b122c0a2136348c2c67f913eeabb2577
```

Using immutable Git-SHA tags provides traceability between:

```text
source commit
     |
     v
container image
     |
     v
GitOps desired state
     |
     v
Kubernetes workload
```

---

# GitOps with Argo CD

Argo CD is installed in EKS and manages the platform Helm release.

The Application definition is stored at:

```text
argocd/applications/platform.yaml
```

The application watches:

```text
Repository:
https://github.com/Habieeb/kubernetes-platform-lab.git

Branch:
main

Path:
helm/platform

Destination namespace:
backend
```

The Application uses automated reconciliation:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true

  syncOptions:
    - CreateNamespace=true
```

This provides three important behaviors.

### Automatic synchronization

Changes committed to the desired-state path are automatically reconciled.

### Pruning

Resources removed from Git can be removed from Kubernetes.

### Self-healing

Supported live-state drift can be reconciled back toward the state declared in Git.

---

# Proven GitOps Deployment

The backend originally used:

```yaml
backend:
  image:
    repository: nginx
    tag: alpine
```

The desired state was changed to the approved ECR artifact:

```yaml
backend:
  image:
    repository: 420796370564.dkr.ecr.eu-west-1.amazonaws.com/platform-lab-app
    tag: 73f0a82aa647063cb18397fb6a0a47b7aecf85b8
```

The GitOps change was committed as:

```text
9ecf07a gitops: deploy backend image from ECR
```

and pushed to `main`.

No direct Kubernetes deployment command was used to perform the release.

---

# Argo CD Verification

Cluster access for the dedicated human administration path is currently invoked using:

```bash
AWS_PROFILE=platform-lab-admin kubectl ...
```

Argo CD status was verified with:

```bash
AWS_PROFILE=platform-lab-admin \
kubectl -n argocd get application platform
```

Observed result:

```text
NAME       SYNC STATUS   HEALTH STATUS
platform   Synced        Healthy
```

This proves Argo CD considers the desired and live application states synchronized and healthy.

---

# Live Deployment Verification

The backend Deployment image was checked directly:

```bash
AWS_PROFILE=platform-lab-admin \
kubectl -n backend get deployments \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[*].image'
```

Observed result:

```text
NAME      IMAGE
backend   420796370564.dkr.ecr.eu-west-1.amazonaws.com/platform-lab-app:73f0a82aa647063cb18397fb6a0a47b7aecf85b8
```

This verifies the EKS Deployment now references the exact ECR image promoted through the secure CI pipeline.

---

# Argo CD CLI

The Argo CD Kubernetes resources can be inspected using `kubectl`.

For richer Argo operations, the Argo CD CLI can also be installed.

Example commands:

```bash
argocd app get platform
```

Display application state and managed resources.

```bash
argocd app diff platform
```

Compare Git desired state with live Kubernetes state.

```bash
argocd app sync platform
```

Request a manual reconciliation.

Because the project uses automated synchronization, routine deployments should **not require manual `argocd app sync` commands**.

---

# Terraform Infrastructure

Terraform manages the AWS infrastructure.

Major resources include:

```text
VPC
Public subnets
EKS
EKS managed bootstrap node
ECR
Karpenter prerequisites
IAM integration
Pod Identity
Spot prerequisites
```

The lab intentionally uses a cost-conscious architecture with public subnets and no NAT Gateway.

That is a **lab design trade-off**, not the recommended networking model for every production environment.

---

# Terraform Delivery Model

Infrastructure changes are owned by Jenkins.

The intended flow is:

```text
Terraform change
      |
      v
Git
      |
      v
Jenkins infra-agent
      |
      +--> terraform fmt
      +--> terraform init
      +--> terraform validate
      +--> Trivy IaC
      +--> terraform plan
      |
      v
Review / approval
      |
      v
terraform apply
```

Terraform should not be manually applied from the developer workstation for normal platform changes.

---

# Packer AMI Pipeline

Packer builds the custom EKS node image used by the platform.

A key design requirement is that Packer should **not build a new AMI for every Terraform change**.

The pipeline calculates a fingerprint from Packer/image inputs.

```text
Packer inputs changed?
        |
   +----+----+
   |         |
  yes        no
   |         |
   v         v
Build AMI   Reuse existing AMI
```

Terraform-only changes therefore reuse the existing approved image.

This keeps AMI creation:

```text
deterministic
intentional
traceable
cost-conscious
```

rather than tying image creation to unrelated infrastructure changes.

---

# Amazon EKS

The platform runs on Amazon EKS.

The cluster uses:

```text
Kubernetes 1.35
Public API endpoint
One t3.small bootstrap managed node
EKS Pod Identity Agent
VPC CNI
CoreDNS
kube-proxy
```

The bootstrap node provides stable initial capacity while Karpenter manages workload-driven capacity.

---

# Human EKS Access

Human cluster administration is separated from Jenkins automation.

The dedicated AWS profile currently used for interactive cluster operations is:

```text
platform-lab-admin
```

Example:

```bash
AWS_PROFILE=platform-lab-admin kubectl get nodes
```

This prevents cluster administration from accidentally depending on unrelated default AWS credentials.

---

# Karpenter

Karpenter provides dynamic EC2 worker capacity.

The platform contains:

```text
EC2NodeClass
NodePool
AWS prerequisites
Pod Identity integration
Node IAM role
EC2 Spot service-linked role
```

The NodePool constrains capacity to appropriate Linux/amd64 instances and allows Karpenter to choose between permitted capacity types according to configuration.

Karpenter scaling has been proven by scheduling application workloads onto dynamically created nodes.

---

# Karpenter NodePool Verification

The NodePool manifest can currently be verified with:

```bash
kubectl apply -f kubernetes/karpenter/nodepool.yaml
```

Observed result:

```text
nodepool.karpenter.sh/platform-lab unchanged
```

This means the submitted manifest matched the existing live NodePool.

The target end state is to place suitable Kubernetes-side Karpenter desired state under Argo CD rather than relying on repeated manual `kubectl apply`.

AWS prerequisites remain Terraform-owned.

---

# Helm

Helm provides reusable Kubernetes templates.

```text
helm/platform/
```

contains the platform application chart.

Argo CD renders this chart rather than Jenkins invoking Helm directly for every deployment.

This gives the responsibility model:

```text
Helm
  = package and templates

Git
  = desired values

Argo CD
  = reconciliation

Kubernetes
  = runtime
```

---

# GitHub Authentication

Jenkins GitOps write access uses a dedicated **GitHub App**.

The Jenkins credential ID is:

```text
github-app-platform-lab
```

The GitHub App has narrowly scoped repository permissions for GitOps updates.

Credentials and private keys are never stored in:

```text
Git
Jenkinsfile
Docker images
Helm values
Terraform source
README
```

The GitHub App used for repository write authentication is conceptually separate from the webhook used to trigger Jenkins builds.

---

# Security Controls

The project implements several security controls.

### No secrets in Git

AWS credentials, Jenkins agent secrets, SonarQube tokens, GitHub App private keys, ECR authorization data, and kubeconfigs must not be committed.

### Dedicated Jenkins agents

Infrastructure and application pipelines execute in separate environments.

### Jenkins controller isolation

The Jenkins controller orchestrates jobs rather than running ordinary pipeline workloads.

### BuildKit instead of Docker socket

Application builds avoid casually mounting the host Docker daemon socket.

### SonarQube Quality Gate

Code quality must pass before image promotion.

### Trivy blocking scan

HIGH and CRITICAL image vulnerabilities block promotion.

### Immutable ECR tags

Released tags cannot silently be replaced.

### GitOps reconciliation

Normal application deployment occurs through Git and Argo CD.

### Temporary ECR authorization protection

Shell tracing is disabled while temporary ECR authorization material is generated:

```bash
set +x

ECR_PASSWORD=$(aws ecr get-login-password ...)
...
unset ECR_PASSWORD AUTH

set -x
```

This prevents temporary registry credentials from being exposed in Jenkins logs.

---

# Verification Commands

## Argo CD

```bash
AWS_PROFILE=platform-lab-admin \
kubectl -n argocd get application platform
```

Detailed status:

```bash
AWS_PROFILE=platform-lab-admin \
kubectl -n argocd get application platform \
  -o jsonpath='Sync={.status.sync.status}{"\n"}Health={.status.health.status}{"\n"}Revision={.status.sync.revision}{"\n"}'
```

---

## Backend Deployment

```bash
AWS_PROFILE=platform-lab-admin \
kubectl -n backend get deployments
```

Show deployed image:

```bash
AWS_PROFILE=platform-lab-admin \
kubectl -n backend get deployments \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[*].image'
```

---

## Backend Pods

```bash
AWS_PROFILE=platform-lab-admin \
kubectl -n backend get pods -o wide
```

Check rollout:

```bash
AWS_PROFILE=platform-lab-admin \
kubectl -n backend rollout status deployment/backend --timeout=5m
```

---

## Runtime Image Digest

```bash
AWS_PROFILE=platform-lab-admin \
kubectl -n backend get pods \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.imageID}{"\n"}{end}{end}'
```

The runtime digest should ultimately be compared against the approved ECR digest:

```text
sha256:e89ead008799d906de1764ab0834e1f9b122c0a2136348c2c67f913eeabb2577
```

---

## Karpenter

```bash
AWS_PROFILE=platform-lab-admin kubectl get nodepools
```

```bash
AWS_PROFILE=platform-lab-admin kubectl get ec2nodeclasses
```

```bash
AWS_PROFILE=platform-lab-admin kubectl get nodes -o wide
```

---

# Current Project Status

| Capability | Status |
|---|---|
| Jenkins controller | ✅ Complete |
| Dedicated infra-agent | ✅ Complete |
| Terraform CI | ✅ Complete |
| AWS VPC | ✅ Complete |
| Amazon EKS | ✅ Complete |
| Amazon ECR | ✅ Complete |
| Custom Packer AMI | ✅ Complete |
| Packer fingerprint/reuse logic | ✅ Complete |
| EKS custom AMI bootstrap | ✅ Complete |
| Karpenter AWS prerequisites | ✅ Complete |
| Karpenter installation | ✅ Complete |
| Karpenter NodePool / EC2NodeClass | ✅ Complete |
| Dynamic node scaling | ✅ Proven |
| Build agent | ✅ Complete |
| Java backend | ✅ Complete |
| SonarQube | ✅ Complete |
| Quality Gate | ✅ Complete |
| BuildKit image build | ✅ Complete |
| Trivy image security gate | ✅ Complete |
| Immutable ECR publication | ✅ Complete |
| Argo CD installation | ✅ Complete |
| Argo CD Application | ✅ Complete |
| Helm GitOps deployment | ✅ Complete |
| Argo Synced / Healthy | ✅ Proven |
| ECR image deployed to backend | ✅ Proven |
| GitHub App for GitOps writes | ✅ Configured |
| Automated Jenkins GitOps promotion | 🚧 Next |
| GitHub webhook -> Jenkins | 🚧 Final verification |
| Karpenter configuration under Argo | 🚧 Planned |
| HPA | 🚧 Planned |
| Ingress | 🚧 Planned |
| BuildKit transport hardening | 🚧 Planned |
| Final end-to-end acceptance | 🚧 Planned |

---

# Current Proven Delivery Path

The following path has now been demonstrated:

```text
Application source
      |
      v
Jenkins
      |
      +--> Tests
      |
      +--> SonarQube
      |
      +--> Quality Gate
      |
      +--> BuildKit
      |
      +--> Trivy
      |
      +--> Skopeo
      |
      v
Amazon ECR
      |
      v
Immutable application image
      |
      v
Helm desired-state update
      |
      v
Git commit
      |
      v
Argo CD
      |
      v
Helm reconciliation
      |
      v
Amazon EKS
      |
      v
backend Deployment
```

The currently deployed backend image has been verified as:

```text
420796370564.dkr.ecr.eu-west-1.amazonaws.com/platform-lab-app:73f0a82aa647063cb18397fb6a0a47b7aecf85b8
```

and the Argo CD Application reports:

```text
Synced
Healthy
```

---

# Remaining Roadmap

The next major milestone is to remove the final manual step from application promotion.

Current proven process:

```text
Jenkins -> ECR
              |
              v
      manual GitOps update
              |
              v
           Argo CD
```

Target:

```text
Jenkins
   |
   +--> Test
   +--> SonarQube
   +--> Quality Gate
   +--> BuildKit
   +--> Trivy
   +--> ECR
   |
   +--> Update Helm image tag
   +--> Commit desired state
   +--> Push using GitHub App
   |
   v
Argo CD
   |
   v
EKS
```

After that:

```text
GitHub webhook
      |
      v
Jenkins automatic CI
      |
      v
ECR
      |
      v
Automated GitOps promotion
      |
      v
Argo CD
      |
      v
EKS
      |
      +--> HPA
      |
      +--> Karpenter
      |
      +--> Ingress
```

Additional hardening work includes:

- authenticated/encrypted BuildKit transport
- Jenkins agent secret rotation
- SonarQube webhook secret
- tighter temporary Packer SSH access
- automated build-agent lifecycle
- Karpenter manifests under GitOps management
- final Spot-capacity validation
- end-to-end release acceptance
- controlled AWS resource cleanup

---

# Production vs Lab Trade-offs

This repository is designed to demonstrate **production engineering patterns**, but it intentionally makes several cost-conscious lab choices.

Examples include:

```text
Public EKS endpoint
Public subnets
No NAT Gateway
Small bootstrap node
Single-node/small-service configurations where appropriate
Local Docker-hosted Jenkins supporting services
```

A production environment would typically evaluate:

```text
Private worker networking
Restricted Kubernetes API access
Highly available CI services
Remote/managed databases
Central secret management
OIDC/federated AWS authentication
Remote Terraform state with strong locking/protection
TLS-authenticated BuildKit
Central logging and monitoring
VPC Flow Logs
Policy enforcement
Backup/disaster recovery
Multi-environment promotion
```

The lab does not pretend these trade-offs are universally production-ready.

Instead, it preserves the **same responsibility boundaries and delivery principles** that can be expanded into a production platform.

---

# Engineering Principles Demonstrated

This project is built around several principles:

1. **Infrastructure is code.**
2. **CI and CD are separate responsibilities.**
3. **Git is the deployment source of truth.**
4. **Images are built once and promoted, not rebuilt after approval.**
5. **Security and quality gates happen before promotion.**
6. **Released image tags are immutable.**
7. **Jenkins credentials are injected at runtime rather than committed.**
8. **Terraform owns AWS infrastructure.**
9. **Argo CD owns Kubernetes application reconciliation.**
10. **Karpenter manages node capacity based on workload demand.**
11. **Helm packages Kubernetes configuration but does not replace GitOps.**
12. **Packer builds a new AMI only when image inputs change.**
13. **Manual commands are used for bootstrap/troubleshooting, not as the final deployment architecture.**
14. **Every automated component should have a clear ownership boundary.**

---

# Documentation

The project is accompanied by a detailed master runbook containing:

```text
Architecture decisions
Exact commands
Actual outputs
Failures encountered
Root causes
Fixes
Security decisions
Terraform implementation
Packer implementation
Jenkins configuration
Karpenter configuration
SonarQube integration
BuildKit workflow
ECR promotion
Argo CD configuration
GitOps verification
Troubleshooting procedures
Remaining implementation roadmap
Interview-ready explanations
```

The runbook is intended to make the environment reproducible and to document not only **what works**, but also **why each design decision was made**.

---

# Final Target

The completed platform is intended to provide the following delivery experience:

```text
Developer
   |
   v
git push
   |
   v
GitHub
   |
   v
Jenkins
   |
   +--> Test
   +--> SonarQube
   +--> Quality Gate
   +--> BuildKit
   +--> Trivy
   +--> Immutable ECR image
   +--> GitOps promotion
   |
   v
Git
   |
   v
Argo CD
   |
   v
Amazon EKS
   |
   +--> Helm workloads
   |
   +--> HPA pod scaling
   |
   +--> Karpenter node scaling
   |
   +--> Ingress
```

The result is a platform where:

**Jenkins builds and validates.  
Terraform provisions.  
Packer creates controlled machine images.  
ECR stores immutable artifacts.  
Git declares desired state.  
Argo CD deploys and reconciles.  
Karpenter provides capacity.  
Kubernetes runs the workload.**

---

## Author

**Habeeb**

Kubernetes Platform Engineering / DevOps Lab
