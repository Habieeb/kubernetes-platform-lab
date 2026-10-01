pipeline {
    agent {
        label 'build-agent'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        SONAR_HOST_URL = 'http://platform-lab-sonarqube:9000'
        BUILDKIT_HOST   = 'tcp://platform-lab-buildkit:1234'
        AWS_REGION      = 'eu-west-1'
        ECR_REPOSITORY  = 'platform-lab-app'
    }

    stages {
        stage('Verify Build Agent') {
            steps {
                sh '''
                    set -eu

                    echo "=== Build Agent ==="
                    whoami
                    hostname

                    echo "=== Tool Versions ==="
                    java -version
                    mvn --version
                    git --version
                    trivy --version
                    aws --version
                    buildctl --version

                    echo "=== BuildKit Connectivity ==="
                    buildctl \
                      --addr "${BUILDKIT_HOST}" \
                      debug workers

                    echo "=== SonarQube Connectivity ==="
                    curl -fsS ${SONAR_HOST_URL}/api/system/status
                    echo
                '''
            }
        }

        stage('Test') {
            steps {
                dir('app/backend') {
                    sh '''
                        set -eu
                        mvn clean test -B
                    '''
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                dir('app/backend') {
                    withSonarQubeEnv(
                        installationName: 'platform-lab-sonarqube',
                        credentialsId: 'sonar-platform-lab-backend'
                    ) {
                        sh '''
                            set -eu

                            mvn org.sonarsource.scanner.maven:sonar-maven-plugin:5.8.0.7211:sonar -B \
                              -Dsonar.projectKey=platform-lab-backend \
                              -Dsonar.host.url=http://platform-lab-sonarqube:9000 \
                              -Dsonar.token=${SONAR_AUTH_TOKEN}
                        '''
                    }
                }
            }
        }

        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Build Container Image') {
            steps {
                dir('app/backend') {
                    sh '''
                        set -eu

                        echo "=== Building backend image with rootless BuildKit ==="

                        rm -f platform-lab-backend.oci.tar

                        buildctl \
                          --addr "${BUILDKIT_HOST}" \
                          build \
                          --frontend dockerfile.v0 \
                          --local context=. \
                          --local dockerfile=. \
                          --opt filename=Dockerfile \
                          --opt platform=linux/amd64 \
                          --output type=oci,dest=platform-lab-backend.oci.tar,name=platform-lab-backend:${GIT_COMMIT}

                        test -s platform-lab-backend.oci.tar

                        echo "=== OCI image artifact created ==="
                        ls -lh platform-lab-backend.oci.tar
                    '''
                }
            }
        }


        stage('Trivy Image Scan') {
            steps {
                dir('app/backend') {
                    sh '''
                        set -eu

                        echo "=== Prepare OCI layout for Trivy ==="

                        rm -rf platform-lab-backend-oci
                        mkdir -p platform-lab-backend-oci

                        tar -xf platform-lab-backend.oci.tar \
                          -C platform-lab-backend-oci

                        test -f platform-lab-backend-oci/index.json
                        test -f platform-lab-backend-oci/oci-layout

                        echo "=== Trivy image vulnerability scan ==="

                        trivy image \
                          --input platform-lab-backend-oci \
                          --severity HIGH,CRITICAL \
                          --exit-code 1 \
                          --timeout 30m \
                          --no-progress
                    '''
                }
            }
        }

        stage('Push Image to ECR') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-credentials',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    dir('app/backend') {
                        sh '''
                            set -eu

                            echo "=== Resolve ECR repository ==="

                            AWS_ACCOUNT_ID=$(aws sts get-caller-identity \
                              --query Account \
                              --output text)

                            ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
                            ECR_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}:${GIT_COMMIT}"

                            echo "Registry: ${ECR_REGISTRY}"
                            echo "Repository: ${ECR_REPOSITORY}"
                            echo "Image tag: ${GIT_COMMIT}"

                            echo "=== Verify ECR repository ==="

                            aws ecr describe-repositories \
                              --region "${AWS_REGION}" \
                              --repository-names "${ECR_REPOSITORY}" \
                              >/dev/null

                            echo "=== Obtain temporary ECR authorization ==="

                            ECR_PASSWORD=$(aws ecr get-login-password \
                              --region "${AWS_REGION}")

                            AUTH=$(printf 'AWS:%s' "${ECR_PASSWORD}" | base64 | tr -d '\\n')

                            mkdir -p "${WORKSPACE}/.docker"

                            cat > "${WORKSPACE}/.docker/config.json" <<EOF
{"auths":{"${ECR_REGISTRY}":{"auth":"${AUTH}"}}}
EOF

                            chmod 600 "${WORKSPACE}/.docker/config.json"

                            export DOCKER_CONFIG="${WORKSPACE}/.docker"

                            echo "=== Push Trivy-approved OCI artifact to ECR ==="

                            skopeo copy \
                              --dest-authfile "${DOCKER_CONFIG}/config.json" \
                              "oci-archive:platform-lab-backend.oci.tar" \
                              "docker://${ECR_IMAGE}"

                            echo "=== Verify image in ECR ==="

                            aws ecr describe-images \
                              --region "${AWS_REGION}" \
                              --repository-name "${ECR_REPOSITORY}" \
                              --image-ids imageTag="${GIT_COMMIT}" \
                              --query 'imageDetails[0].{Digest:imageDigest,Tag:imageTags[0]}' \
                              --output table

                            rm -rf "${WORKSPACE}/.docker"

                            echo "=== ECR publication completed ==="
                            echo "Published immutable tag: ${GIT_COMMIT}"
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            sh '''
                rm -rf "${WORKSPACE}/.docker" 2>/dev/null || true
                rm -f "${WORKSPACE}/app/backend/platform-lab-backend.oci.tar" 2>/dev/null || true
            '''
        }

        success {
            echo 'Backend tests, SonarQube Quality Gate, BuildKit build, Trivy scan, and ECR publication passed.'
        }

        failure {
            echo 'Backend CI failed. Review the failed stage; an image is not promoted after a failed gate.'
        }
    }
}
