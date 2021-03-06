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
    // MVN_OPTION = ""
    // TRACE = "true"
    KUBERNETES_VERSION="1.13.5"
    DEV_NAMESPACE="dev"  // 各环境namespace
    UAT_NAMESPACE="uat"
    HELM_VERSION="2.11.0"
    HELM_REPO="https://ygqygq2.github.io/charts"
    HELM_REPO_NAME="utcook"
    HELM_HOST="tiller-deploy.kube-system:44134"

    CHART_NAME="utcook"  // chart模板名
    CHART_VERSION="1.1.0"  // chart模板版本
    CONTAINER_REPO="reg.utcook.com"  // 上传docker仓库
    CONTAINER_PROJECT="pub"  // docker仓库项目
    DOCKER_HOST="192.168.105.71:2375"
    DOCKER_USER="docker"
    DOCKER_PASSWD="Dev12345"
    DOCKER_DRIVER="overlay2"
    SONAR_URL="https://sonar.utcook.com"
    SONAR_TOKEN="d5680c3779c1f37680b887cfd1a2619914552034"
    MAVEN_HOST="https://nexus.utcook.com"
    DOCKER_BUILD="true"  // 添加注释或者设置为false，不进行docker build
    STAGING_ENABLED="true"  // 添加注释或者设置为false,不部署dev环境
    ZAPROXY_DISABLED="true"  // 设置为true,不进行zaproxy扫描
    TEST_DISABLED="true"  // 设置为true,不进行test任务
    // CODE_QUALITY_DISABLED="true"  // 取消注释，设置为true，不进行代码质量扫描

    // POD个数
    REPLICAS="1"  // 默认为1
    UAT_REPLICAS="1"    
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
