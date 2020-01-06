#!/usr/bin/env bash

# Auto DevOps variables and functions
[[ "$TRACE" ]] && set -x
export INIT_DIR=$(pwd)

export CI_COMMIT_SHORT_SHA=${GIT_COMMIT:0:8}
if [ "$CI_COMMIT_REF_NAME" == "master" ]; then
  export CONTAINER_TAG="stable"
fi

TMP_URL=$(echo ${GIT_URL} | sed -e 's#.*@##' -e 's#.git$##')
CI_PROJECT_PATH_SLUG=$(echo ${TMP_URL#*/} | sed -e 's@_@-@g' -e 's@/@-@g' \
  | tr '[:upper:]' '[:lower:]' | sed 's@\.@@g') 
CI_PROJECT_NAME=$(basename ${TMP_URL#*/})
CI_PROJECT_VISIBILITY="public"


function registry_login() {
  # 使用Harbor
  if [[ -n "$DOCKER_USER" ]]; then
    echo "Logging to Harbor..."
    docker login -u "$DOCKER_USER" -p "$DOCKER_PASSWD" "$CONTAINER_REPO"
    echo ""
  fi   

}

function get_replicas() {
  local track="${1:-stable}"
  local percentage="${2:-100}"

  env_track=$( echo $track | tr  '[:lower:]'  '[:upper:]' )
  env_slug=$( echo ${CI_ENVIRONMENT_SLUG//-/_} | tr  '[:lower:]'  '[:upper:]' )

  if [[ "$track" == "stable" ]] || [[ "$track" == "rollout" ]]; then
    # for stable track get number of replicas from `PRODUCTION_REPLICAS`
    eval new_replicas=\$${env_slug}_REPLICAS
    if [[ -z "$new_replicas" ]]; then
      new_replicas=$REPLICAS
    fi
  else
    # for all tracks get number of replicas from `CANARY_PRODUCTION_REPLICAS`
    eval new_replicas=\$${env_track}_${env_slug}_REPLICAS
    if [[ -z "$new_replicas" ]]; then
      eval new_replicas=\${env_track}_REPLICAS
    fi
  fi

  replicas="${new_replicas:-1}"
  replicas="$(($replicas * $percentage / 100))"

  # always return at least one replicas
  if [[ $replicas -gt 0 ]]; then
    echo "$replicas"
  else
    echo 1
  fi
}

function deploy() {
  local KUBE_NAMESPACE="${1-${DEV_NAMESPACE}}"
  local track="${2-stable}"
  local percentage="${3:-100}"
  local name
  local replicas="1"
    
  local xmlns=$(grep 'xmlns=' pom.xml|sed -r 's@.*xmlns=(.*)@\1@'|awk '{print $1}'|sed 's@"@@g')
  image_name=$(xmlstarlet sel -N d=$xmlns -T -t -m "//d:project" -v d:artifactId -n pom.xml)
  image_tag=$(xmlstarlet sel -N d=$xmlns -T -t -m "//d:project" -v d:version -n pom.xml)-$CI_COMMIT_SHORT_SHA
  image_url=$CONTAINER_REPO/$CONTAINER_PROJECT/${image_name}

  # if track is different than stable,
  # re-use all attached resources
  if [[ "$track" != "stable" ]]; then
    name="${KUBE_NAMESPACE}-${CI_PROJECT_PATH_SLUG}-${track}"
    if [ ${#name} -gt 53 ]; then
      # 如果名字超过53个字符，可用如下定义
      name="${KUBE_NAMESPACE}-${CI_PROJECT_NAME}-${track}"
    fi
  else
    name="${KUBE_NAMESPACE}-${CI_PROJECT_PATH_SLUG}"
    if [ ${#name} -gt 53 ]; then
      # 如果名字超过53个字符，可用如下定义
      name="${KUBE_NAMESPACE}-${CI_PROJECT_NAME}"
    fi
  fi

  # helm名只允许小写和-
  name=$(echo ${name//_/-} | tr '[:upper:]' '[:lower:]' | sed 's@\.@@g')

  replicas=$(get_replicas "$track" "$percentage")

  if [[ "$CI_PROJECT_VISIBILITY" != "public" ]]; then
    secret_name='gitlab-registry'
  else
    secret_name=''
  fi
    # 判断是否有自定义values.yaml
    if [ -f ci/${KUBE_NAMESPACE}/${CI_PROJECT_NAME}-values.yaml ]; then
      echo "Use the values file: ci/${KUBE_NAMESPACE}/${CI_PROJECT_NAME}-values.yaml"
      values_option="-f ci/${KUBE_NAMESPACE}/${CI_PROJECT_NAME}-values.yaml"
    else
      echo "Not found the values file: ci/${KUBE_NAMESPACE}/${CI_PROJECT_NAME}-values.yaml"
      values_option=""
    fi
    
    if [[ -z "$(helm ls -q "^$name$")" ]]; then
      helm upgrade --install \
        --wait \
        --namespace="$KUBE_NAMESPACE" \
        --set image.repository="${image_url}" \
        --set image.tag="${image_tag}" \
        --set replicaCount="$replicas" \
        --force \
        $values_option \
        "$name" \
        chart/
    else
      helm upgrade --reuse-values --install \
        --wait \
        --namespace="$KUBE_NAMESPACE" \
        --set image.repository="${image_url}" \
        --set image.tag="${image_tag}" \
        --set replicaCount="$replicas" \
        --force \
        $values_option \
        "$name" \
        chart/
    fi
    
    kubectl rollout status -n "$KUBE_NAMESPACE" -w "deployment/${name}-${CHART_NAME}" \
      || kubectl rollout status -n "$KUBE_NAMESPACE" -w "statefulset/${name}-${CHART_NAME}" \
      || kubectl rollout status -n "$KUBE_NAMESPACE" -w "deployment/${name}" \
      || kubectl rollout status -n "$KUBE_NAMESPACE" -w "statefulset/${name}"

}

function scale() {
  local KUBE_NAMESPACE="${1-${DEV_NAMESPACE}}"
  local track="${2-stable}"
  local percentage="${3:-100}"
  local name

  if [[ "$track" != "stable" ]]; then
    name="${KUBE_NAMESPACE}-${CI_PROJECT_PATH_SLUG}-${track}"
    if [ ${#name} -gt 53 ]; then
      # 如果名字超过53个字符，可用如下定义
      name="${KUBE_NAMESPACE}-${CI_PROJECT_NAME}-${track}"
    fi
  else
    name="${KUBE_NAMESPACE}-${CI_PROJECT_PATH_SLUG}"
    if [ ${#name} -gt 53 ]; then
      # 如果名字超过53个字符，可用如下定义
      name="${KUBE_NAMESPACE}-${CI_PROJECT_NAME}"
    fi
  fi


  # helm名只允许小写和-
  name=$(echo ${name//_/-} | tr '[:upper:]' '[:lower:]' | sed 's@\.@@g') 

  replicas=$(get_replicas "$track" "$percentage")

  if [[ -n "$(helm ls -q "^$name$")" ]]; then
    helm upgrade --reuse-values \
      --wait \
      --set replicaCount="$replicas" \
      --namespace="$KUBE_NAMESPACE" \
      "$name" \
      chart/
  fi
}

function install_dependencies() {
  # 基础镜像已经安装，此处只打印版本
  helm version
  tiller -version
  kubectl version
}

function setup_docker() {
  if ! docker info &>/dev/null; then
    if [ -z "$DOCKER_HOST" -a "$KUBERNETES_PORT" ]; then
      export DOCKER_HOST='tcp://localhost:2375'
    fi
  fi
}

function download_chart() {
  if [[ ! -d chart ]]; then
    auto_chart=${AUTO_DEVOPS_CHART:-${HELM_REPO_NAME}/${CHART_NAME}}
    auto_chart_name=$(basename $auto_chart)
    auto_chart_name=${auto_chart_name%.tgz}
    auto_chart_name=${auto_chart_name%.tar.gz}
  else
    auto_chart="chart"
    auto_chart_name="chart"
  fi

  # 添加内网chart
  helm init --client-only --stable-repo-url ${HELM_REPO}
  helm repo add ${HELM_REPO_NAME} ${HELM_REPO}
  if [[ ! -d "$auto_chart" ]]; then
    helm fetch ${auto_chart} --untar --version=$CHART_VERSION
  fi
  if [ "$auto_chart_name" != "chart" ]; then
    mv ${auto_chart_name} chart
  fi

  helm dependency update chart/
  helm dependency build chart/
}

function ensure_namespace() {
  local KUBE_NAMESPACE="$1"
  kubectl describe namespace "$KUBE_NAMESPACE" || kubectl create namespace "$KUBE_NAMESPACE"
}

function check_kube_domain() {
  if [ -z ${AUTO_DEVOPS_DOMAIN+x} ]; then
    echo "In order to deploy or use Review Apps, AUTO_DEVOPS_DOMAIN variable must be set"
    echo "You can do it in Auto DevOps project settings or defining a variable at group or project level"
    echo "You can also manually add it in .gitlab-ci.yml"
    false
  else
    true
  fi
}

function maven_setting() {
  # registry_login
  # 设置maven setting.xml
  cat > /usr/share/maven/conf/settings.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>    
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0
    https://maven.apache.org/xsd/settings-1.0.0.xsd">
  <localRepository>/usr/share/maven/ref/repository</localRepository>
  <servers>
    <server>
      <id>dockerId</id>
      <username>${DOCKER_USER}</username>
      <password>${DOCKER_PASSWD}</password>
      <configuration>
        <email></email>
      </configuration>
    </server>
    <server>
      <id>${CONTAINER_REPO}</id>
      <username>${DOCKER_USER}</username>
      <password>${DOCKER_PASSWD}</password>
      <configuration>
        <email></email>
      </configuration>
    </server>      
    <server>
      <id>nexusId</id>
      <username>${NEXUS_USER}</username>
      <password>${NEXUS_PASSWD}</password>
      <configuration>
        <email></email>
      </configuration>
    </server>
  </servers>
</settings>
EOF
}

function build() {
  maven_setting

  # 根据pom.xml判断是否进行mvn操作
  [ ! -f "pom.xml" ] \
    && echo "Not a maven project. Stop." \
    && exit 1
  # 获取xml namespace
  local xmlns=$(grep 'xmlns=' pom.xml|sed -r 's@.*xmlns=(.*)@\1@'|awk '{print $1}'|sed 's@"@@g')
  # 更新docker仓库
  \cp pom.xml .tmp-pom.xml
  xmlstarlet ed -N d=$xmlns -u "//d:project/d:properties/d:registryUrl" \
    -v $CONTAINER_REPO .tmp-pom.xml > tmp-pom.xml
  mv tmp-pom.xml .tmp-pom.xml
  # 更新docker仓库项目
  xmlstarlet ed -N d=$xmlns -u "//d:project/d:properties/d:registryProject" \
    -v $CONTAINER_PROJECT .tmp-pom.xml > tmp-pom.xml
  mv tmp-pom.xml .tmp-pom.xml
  # 更新docker tag引入环境变量
  xmlstarlet ed -N d=$xmlns -u "//d:project/d:properties/d:dockerImageTag" \
    -v '${project.version}-${env.CI_COMMIT_SHORT_SHA}' .tmp-pom.xml > tmp-pom.xml
  mv tmp-pom.xml ci-pom.xml

  # 进行单元测试，需要有mvn_test.txt文件作为启动标识
  if [ -f mvn_test.txt ]; then
    echo "mvn test -B -f ci-pom.xml"
    mvn clean test -B -f ci-pom.xml && cat target/site/jacoco/index.html || exit 1
  fi

  # 进行sonar代码质量扫描
  echo "mvn sonar"
  mvn sonar:sonar -Dsonar.java.binaries=target/sonar -Dsonar.host.url=${SONAR_URL} -Dsonar.login=${SONAR_TOKEN}

  # 执行mvn install
  echo "mvn install -B -f ci-pom.xml -DskipTests"
  mvn install -B -f ci-pom.xml -DskipTests $MVN_OPTION
}
    
function test_image() {
  # 容器能运行60秒，即表示image正常（未测试程序逻辑）
  return 0
  local xmlns=$(grep 'xmlns=' pom.xml|sed -r 's@.*xmlns=(.*)@\1@'|awk '{print $1}'|sed 's@"@@g')
  image_name=$(xmlstarlet sel -N d=$xmlns -T -t -m "//d:project" -v d:artifactId -n pom.xml)
  image_tag=$(xmlstarlet sel -N d=$xmlns -T -t -m "//d:project" -v d:version -n pom.xml)-$CI_COMMIT_SHORT_SHA
  image_url=$CONTAINER_REPO/$CONTAINER_PROJECT/${image_name}

  echo "Start comtainer 【$CI_PROJECT_PATH_SLUG】."
  registry_login
  docker run --name $CI_PROJECT_PATH_SLUG -d $image_url:$image_tag
  sleep 60
  docker exec -i $CI_PROJECT_PATH_SLUG /bin/sh -c "true"
  docker rm -f $CI_PROJECT_PATH_SLUG
}

function initialize_tiller() {
  echo "Checking Tiller..."
  if [ -z "${HELM_HOST}" ]; then
    export HELM_HOST=":44134"
    tiller -listen ${HELM_HOST} -alsologtostderr > /dev/null 2>&1 &
    echo "Tiller is listening on ${HELM_HOST}"
  fi

  if ! helm version --debug; then
    echo "Failed to init Tiller."
    return 1
  fi
  echo ""
}

function create_secret() {
  local KUBE_NAMESPACE="$1"
  echo "Create secret..."
  if [[ "$CI_PROJECT_VISIBILITY" == "public" ]]; then
    return
  fi

  kubectl create secret -n "$KUBE_NAMESPACE" \
    docker-registry gitlab-registry \
    --docker-server="$CONTAINER_REPO" \
    --docker-username="${DOCKER_USER}" \
    --docker-password="${DOCKER_PASSWD}" \
    --docker-email="$GIT_COMMITTER_EMAIL" \
    -o yaml --dry-run | kubectl replace -n "$KUBE_NAMESPACE" --force -f -
}

function zaproxy() {
  export CI_ENVIRONMENT_URL=$(cat environment_url.txt)
  mkdir -p /zap/wrk/
  zap-baseline.py -t "$CI_ENVIRONMENT_URL" -g gen.conf -r report.html || true
  cp /zap/wrk/report.html .
}

function persist_environment_url() {
    echo $CI_ENVIRONMENT_URL > environment_url.txt
}

function delete() {
  local KUBE_NAMESPACE="${1-${DEV_NAMESPACE}}"
  local track="${2-stable}"
  local name="${KUBE_NAMESPACE}-${CI_PROJECT_NAME}"

  if [[ "$track" != "stable" ]]; then
    name="${KUBE_NAMESPACE}-${CI_PROJECT_NAME}-${track}"
  fi
  
  # helm名只允许小写和-
  name=$(echo ${name//_/-} | tr '[:upper:]' '[:lower:]')    

  if [[ -n "$(helm ls -q "^$name$")" ]]; then
    helm delete --purge "$name"
  fi
}

# 支持定制化function以覆盖默认设置
[ -f scripts/function.sh ] && source scripts/function.sh || true
