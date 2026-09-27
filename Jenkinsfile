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
                            terraform plan -input=false -out=tfplan
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
                            terraform apply -input=false tfplan
                        '''
                    }
                }
            }
        }
    }

    post {
        success {
            echo 'Infrastructure pipeline completed successfully.'
        }

        failure {
            echo 'Infrastructure pipeline failed. Review the failed stage.'
        }
    }
}
