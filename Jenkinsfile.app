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

                            mvn sonar:sonar -B \
                              -Dsonar.projectKey=platform-lab-backend \
                              -Dsonar.host.url=${SONAR_HOST_URL} \
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
    }

    post {
        success {
            echo 'Backend CI validation and SonarQube Quality Gate passed.'
        }

        failure {
            echo 'Backend CI validation failed. Review the failed stage.'
        }
    }
}
