pipeline {
  options {
    // 流水线超时设置
    timeout(time:1, unit: 'HOURS')
    //保持构建的最大个数
    buildDiscarder(logRotator(numToKeepStr: '10'))
    gitLabConnection("gitlab")
  }

  triggers {
    gitlab(triggerOnPush: true,
      triggerOnMergeRequest: true,
      branchFilterType: "All",
      secretToken: "t8vcxwuza023ehzcftzr5a74vkpto6xr")
  }

  agent {
    // k8s pod设置
    kubernetes {
      label "jenkins-slave-${UUID.randomUUID().toString()}"
      yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins-role: slave-docker
spec:
  containers:
  - name: maven   
    image: ygqygq2/maven:latest
    command:
    - cat
    tty: true
    volumeMounts:
    - name: maven-data
      mountPath: /root/.m2/repository  
  - name: helm   
    image: ygqygq2/k8s-alpine:latest
    command:
    - cat
    tty: true
  volumes:
  - name: maven-data
    persistentVolumeClaim:
      claimName: jenkins-maven        
"""
    }
  }

  environment {
    // 全局环境变量
    KUBECONFIG = credentials('kubernetes-admin-config')
    CI_ENVIRONMENT_SLUG = "staging"
    TRACE = "true"
  }  

  stages {
    stage('Maven CI') {
      steps {
        container('maven') {
          ansiColor('xterm') {
            sh """
              source scripts/global_functions.sh
              setup_docker
              build
            """
          }
        }          
      }
    }

    stage('Helm deploy') {
      steps {
        container('helm') {
          ansiColor('xterm') {
            sh """
              source scripts/global_functions.sh
              install_dependencies
              download_chart
              ensure_namespace $DEV_NAMESPACE
              initialize_tiller
              create_secret
              deploy $DEV_NAMESPACE
            """
          }
        }          
      }
    }
  }
      
  post {
      aborted {
          echo "post condition executed: aborted ..."
      }        
      failure {
          updateGitlabCommitStatus name: "build", state: "failed"
      }
      success {
          updateGitlabCommitStatus name: "build", state: "success"
      }
  }
}
