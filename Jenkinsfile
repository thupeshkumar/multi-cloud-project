pipeline {
  agent any
  options {
    skipDefaultCheckout(true)
    disableConcurrentBuilds()
    timestamps()
    timeout(time: 45, unit: 'MINUTES')
    buildDiscarder(logRotator(numToKeepStr: '15'))
  }
  parameters {
    booleanParam(name: 'DEPLOY_APP', defaultValue: false,
      description: 'Deploy the static Nginx page after CI and manual approval')
  }
  triggers { pollSCM('H/5 * * * *') }
  stages {
    stage('Checkout') {
      steps { checkout scm }
    }
    stage('Terraform format') {
      steps {
        dir('terraform') { sh 'terraform fmt -check -recursive' }
      }
    }
    stage('Terraform validate') {
      steps {
        dir('terraform') {
          sh 'terraform init -backend=false -input=false'
          sh 'terraform validate -no-color'
        }
      }
    }
    stage('Deployment script check') {
      steps {
        sh 'bash -n scripts/jenkins-deploy.sh'
        sh 'shellcheck scripts/jenkins-deploy.sh'
        sh 'test -s app/index.html.template'
        sh 'test -s jenkins/targets.txt'
      }
    }
    stage('Deployment approval') {
      when { expression { params.DEPLOY_APP } }
      options { timeout(time: 10, unit: 'MINUTES') }
      steps {
        input message: 'Deploy this checked-out revision to the three configured lab VMs?', ok: 'Deploy'
      }
    }
    stage('Deploy and verify application') {
      when { expression { params.DEPLOY_APP } }
      steps {
        withCredentials([file(credentialsId: 'cloud-known-hosts', variable: 'KNOWN_HOSTS_FILE')]) {
          sshagent(credentials: ['cloud-vm-ssh']) {
            sh 'bash scripts/jenkins-deploy.sh'
          }
        }
      }
    }
  }
  post {
    always {
      archiveArtifacts artifacts: 'deployment-evidence/**',
        allowEmptyArchive: true, fingerprint: true
    }
  }
}
