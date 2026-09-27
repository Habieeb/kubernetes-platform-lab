pipeline {
    agent {
        label 'infra-agent'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    parameters {
        booleanParam(
            name: 'BUILD_NEW_AMI',
            defaultValue: false,
            description: 'Build a new EKS worker AMI with Packer'
        )

        string(
            name: 'EXISTING_AMI_ID',
            defaultValue: '',
            description: 'Existing custom AMI to use when BUILD_NEW_AMI is false'
        )
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

        stage('Packer Preflight') {
            when {
                expression {
                    return params.BUILD_NEW_AMI
                }
            }


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

                        echo "=== AWS Identity ==="
                        aws sts get-caller-identity

                        echo "=== Default VPC ==="
                        DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
                            --region "${AWS_REGION}" \
                            --filters "Name=is-default,Values=true" \
                            --query 'Vpcs[0].VpcId' \
                            --output text)

                        if [ -z "${DEFAULT_VPC_ID}" ] || [ "${DEFAULT_VPC_ID}" = "None" ]; then
                            echo "ERROR: No default VPC found in ${AWS_REGION}."
                            echo "Packer needs suitable networking for its temporary builder."
                            exit 1
                        fi

                        echo "Default VPC: ${DEFAULT_VPC_ID}"

                        echo "=== Default Subnets ==="
                        DEFAULT_SUBNET_COUNT=$(aws ec2 describe-subnets \
                            --region "${AWS_REGION}" \
                            --filters \
                                "Name=vpc-id,Values=${DEFAULT_VPC_ID}" \
                                "Name=default-for-az,Values=true" \
                            --query 'length(Subnets)' \
                            --output text)

                        if [ "${DEFAULT_SUBNET_COUNT}" -lt 1 ]; then
                            echo "ERROR: No default subnet found in ${DEFAULT_VPC_ID}."
                            exit 1
                        fi

                        echo "Default subnets found: ${DEFAULT_SUBNET_COUNT}"

                        echo "=== EKS 1.35 AL2023 Source AMI ==="
                        SOURCE_AMI_ID=$(aws ssm get-parameter \
                            --region "${AWS_REGION}" \
                            --name '/aws/service/eks/optimized-ami/1.35/amazon-linux-2023/x86_64/standard/recommended/image_id' \
                            --query 'Parameter.Value' \
                            --output text)

                        if [ -z "${SOURCE_AMI_ID}" ] || [ "${SOURCE_AMI_ID}" = "None" ]; then
                            echo "ERROR: Could not resolve the EKS source AMI."
                            exit 1
                        fi

                        echo "Source AMI: ${SOURCE_AMI_ID}"

                        echo "=== Verify Source AMI ==="
                        aws ec2 describe-images \
                            --region "${AWS_REGION}" \
                            --image-ids "${SOURCE_AMI_ID}" \
                            --query 'Images[0].[ImageId,Name,OwnerId,Architecture]' \
                            --output table

                        echo "=== Packer Preflight PASSED ==="
                    '''
                }
            }
        }

        stage('Approve Packer Build') {
            when {
                expression {
                    return params.BUILD_NEW_AMI
                }
            }

            steps {
                input message: 'Packer will launch temporary AWS resources and create an AMI/EBS snapshot. Build the custom EKS node AMI?',
                      ok: 'Build AMI'
            }
        }

        stage('Packer Build') {
            when {
                expression {
                    return params.BUILD_NEW_AMI
                }
            }


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
            when {
                expression {
                    return params.BUILD_NEW_AMI
                }
            }


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

        stage('Select Existing AMI') {
            when {
                expression {
                    return !params.BUILD_NEW_AMI
                }
            }

            steps {
                script {
                    if (!params.EXISTING_AMI_ID?.trim()) {
                        error('EXISTING_AMI_ID is required when BUILD_NEW_AMI is false')
                    }

                    env.NODE_AMI_ID = params.EXISTING_AMI_ID.trim()

                    echo "Using existing AMI: ${env.NODE_AMI_ID}"
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
