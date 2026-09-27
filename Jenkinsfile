pipeline {
    agent {
        label 'infra-agent'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        AWS_REGION = 'eu-west-1'
    }

    stages {
        stage('Verify Tooling') {
            steps {
                sh '''
                    set -eu

                    echo "=== Jenkins Agent ==="
                    whoami
                    hostname

                    echo "=== Tool Versions ==="
                    terraform version
                    packer version
                    trivy --version
                    aws --version
                    git --version
                '''
            }
        }

        stage('Verify AWS Identity') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh '''
                        set -eu
                        echo "=== AWS Identity Check ==="
                        aws sts get-caller-identity
                    '''
                }
            }
        }

        stage('Terraform Format') {
            steps {
                dir('terraform') {
                    sh '''
                        set -eu
                        terraform fmt -check -recursive
                    '''
                }
            }
        }

        stage('Terraform Init') {
            steps {
                dir('terraform') {
                    sh '''
                        set -eu
                        terraform init -input=false
                    '''
                }
            }
        }

        stage('Terraform Validate') {
            steps {
                dir('terraform') {
                    sh '''
                        set -eu
                        terraform validate
                    '''
                }
            }
        }

        stage('Trivy IaC Scan') {
            steps {
                sh '''
                    set -eu
                    trivy config --skip-dirs 'terraform/.terraform/**' terraform/
                '''
            }
        }

        stage('Packer Init and Validate') {
            steps {
                dir('packer') {
                    sh '''
                        set -eu

                        echo "=== Packer Init ==="
                        packer init .

                        echo "=== Packer Format Check ==="
                        packer fmt -check .

                        echo "=== Packer Validate ==="
                        packer validate .
                    '''
                }
            }
        }

        stage('Approve Packer Build') {
            steps {
                input message: 'Packer will launch temporary AWS resources and create an AMI/EBS snapshot. Build the custom EKS node AMI?',
                      ok: 'Build AMI'
            }
        }

        stage('Packer Build') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    dir('packer') {
                        sh '''
                            set -eu

                            echo "=== Packer Build ==="

                            rm -f manifest.json

                            packer build \
                              -var "aws_region=${AWS_REGION}" \
                              .

                            test -f manifest.json

                            echo "=== Packer Manifest ==="
                            cat manifest.json
                        '''
                    }
                }
            }
        }

        stage('Capture Packer AMI') {
            steps {
                script {
                    env.NODE_AMI_ID = sh(
                        script: '''
                            set -eu

                            python3 - <<'PY'
import json

with open("packer/manifest.json") as f:
    manifest = json.load(f)

artifact_id = manifest["builds"][-1]["artifact_id"]

# amazon-ebs manifest artifact_id is normally:
# eu-west-1:ami-xxxxxxxxxxxxxxxxx
ami_id = artifact_id.split(":")[-1]

if not ami_id.startswith("ami-"):
    raise SystemExit(
        "Unable to extract AMI ID from artifact_id: " + artifact_id
    )

print(ami_id)
PY
                        ''',
                        returnStdout: true
                    ).trim()

                    echo "Packer created AMI: ${env.NODE_AMI_ID}"
                }
            }
        }

        stage('Verify Custom AMI') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh '''
                        set -eu

                        echo "=== Verify Custom AMI ==="

                        aws ec2 describe-images \
                          --region "${AWS_REGION}" \
                          --image-ids "${NODE_AMI_ID}" \
                          --query 'Images[0].[ImageId,Name,State,Architecture]' \
                          --output table
                    '''
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    dir('terraform') {
                        sh '''
                            set -eu

                            echo "=== Terraform Plan ==="
                            echo "Using Packer AMI: ${NODE_AMI_ID}"

                            terraform plan \
                              -input=false \
                              -var="node_ami_id=${NODE_AMI_ID}" \
                              -out=tfplan

                            terraform show -no-color tfplan > tfplan.txt
                        '''
                    }
                }
            }
        }

        stage('Approval') {
            steps {
                input message: 'Review Terraform plan. Apply these changes to AWS?',
                      ok: 'Apply'
            }
        }

        stage('Terraform Apply') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    dir('terraform') {
                        sh '''
                            set -eu

                            echo "=== Terraform Apply ==="
                            echo "Using reviewed Packer AMI: ${NODE_AMI_ID}"

                            terraform apply -input=false tfplan
                        '''
                    }
                }
            }
        }
    }

    post {
        success {
            echo 'Packer AMI and infrastructure pipeline completed successfully.'
        }

        failure {
            echo 'Infrastructure pipeline failed. Review the failed stage.'
        }

        aborted {
            echo 'Infrastructure pipeline was aborted.'
        }
    }
}
