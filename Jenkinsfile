pipeline {
    agent {
        label 'infra-agent'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
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
    }

    post {
        success {
            echo 'Infrastructure validation completed successfully.'
        }

        failure {
            echo 'Infrastructure validation failed. Review the failed stage before proceeding.'
        }
    }
}
