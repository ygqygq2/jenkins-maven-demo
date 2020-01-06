[![pipeline status](https://gitlab.utcook.com/share/maven-ci-demo/badges/master/pipeline.svg)](https://gitlab.utcook.com/share/maven-ci-demo/commits/master)
[![coverage report](https://gitlab.utcook.com/share/maven-ci-demo/badges/master/coverage.svg)](https://gitlab.utcook.com/share/maven-ci-demo/commits/master)

## 1. 环境

**平台或软件版本**
kubernetes: `1.13.4`    
gitlab-ce: `docker版12.0.2`    

## 2. gitlab流水线说明
- [x] 必选
- [ ] 可选

1. - [x] 请详细阅读`README.md`和`.gitlab-ci.yml`；
2. - [x] gitlab ci/cd触发条件是手动或者仓库接收到push/merge和通过触发器url；
3. - [x] 请保证项目名和项目路径中的项目名大小写等一致；
4. - [x] 放置`.gitlab-ci.yml`在仓库根目录，其内容参考[.gitlab-ci.yml](./.gitlab-ci.yml)，注意部分修改的内容；
5. - [x] maven项目中配置`pom.xml`；
6. - [x] 增加项目helm部署的配置目录和文件: `ci/环境namespace名/项目名-values.yaml`；
7. - [x] 配置项目徽章：项目设置-->通用-->徽章；
8. - [x] 平时自行清理docker仓库不使用的旧镜像https://reg.utcook.com/；
9. - [ ] 代码覆盖率正则设置(需要jacoco插件和编写单元测试)为`Total.*?([0-9]{1,3})%`：项目设置-->CI/CD-->流水线通用设置-->测试覆盖率解析；
10. - [ ] `.codeclimate.yml`代码质量分析设置

## 3. `.gitlab-ci.yml`要点说明
* 为了尽可能简洁和统一管理，一些CI变量和步骤使用include方式处理，注释部分可自行删除；
* `.gitlab-ci.yml`中自定义的job覆盖include中的job，以达到定制化目的；
* 注意`.gitlab-ci.yml`的include下`ref`模板引用分支设置为`master`；

## 4. maven `pom.xml`配置说明
1. maven项目编译通过`pom.xml`控制，外部控制gitlab流水线可以通过传递环境变量；    
2. maven对程序进行打包成docker image，通过docker image的tag名包含commit hash值，可以确定程序在git中的位置。自动打包docker image的命名规则：`${project.artifactId}:${project.version}-${env.CI_COMMIT_SHORT_SHA}`；
3. `pom.xml`请整理和定义好docker仓库相关变量；
4. `pom.xml`中build的install部分请使用如下`docker-maven-plugin`插件内容。其效果是`mvn install`会进行`docker build/tag/push`等操作；
5. `pom.xml`中build的test部分请添加jacoco插件，并添加`mvn test`标识文件`mvn_test.txt`，jacoco插件内容如下。其效果是`mvn test`后会产生代码覆盖率报告`target/site/jacoco/index.html`，CI过程中使用`cat`命令将其内容显示到CI日志中，gitlab会根据设置的正则表达式，自动获取到代码覆盖率；
6. maven `settings.xml`的docker仓库server定义为`dockerId`，使用`DOCKER_USER`、`DOCKER_PASSWD`取自CI过程中环境变量，即`.gitlab-ci.yml`中定义的变量。`pom.xml`中引用时注意。
7. maven `settings.xml`的nexus仓库server`nexusId`，使用`NEXUS_USER`、`NEXUS_PASSWD`取自CI过程中环境变量，即`.gitlab-ci.yml`中定义的变量。`pom.xml`中引用时注意。

`docker仓库相关变量`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd
/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.ut.test</groupId>
  <artifactId>test</artifactId>
  <version>1.0.2</version>
  <properties>
    <!-- 仓库地址 -->
    <registryUrl>reg.utcook.com</registryUrl>
    <!--注意仓库名 -->
    <registryProject>pub</registryProject>
    <!-- docker iamge名 -->
    <dockerImageName>${project.artifactId}</dockerImageName>
    <!-- docker iamge tag -->
    <dockerImageTag>${project.version}</dockerImageTag>
    <!-- docker image 完整url -->
    <dockerImageUrl>${registryUrl}/${registryProject}/${dockerImageName}:${dockerImageTag}</dockerImageUrl>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    <java.version>1.8</java.version>
    <maven.compiler.source>1.8</maven.compiler.source>
    <maven.compiler.target>1.8</maven.compiler.target>
  </properties>
```

`docker-maven-plugin`插件内容整理：

```xml
             <plugin>
                <groupId>com.spotify</groupId>
                <artifactId>docker-maven-plugin</artifactId>
                <version>1.0.0</version>
                <configuration>
                    <dockerHost>http://192.168.105.71:2375</dockerHost>
                    <serverId>dockerId</serverId>
                    <imageName>${dockerImageUrl}</imageName>
                    <baseImage>openjdk:8-jdk-alpine</baseImage>
                    <entryPoint>["java", "-Xdebug", "-Xnoagent", "-Djava.compiler=NONE", "-Duser.timezone=GMT+08", "-Xrunjdwp:transport=dt_socket,address=5005,server=y,suspend=n","-Djava.security.egd=file:/dev/./urandom", "-jar", "/${project.build.finalName}.jar"]</entryPoint>
                    <resources>
                        <resource>
                            <targetPath>/</targetPath>
                            <directory>${project.build.directory}</directory>
                            <include>${project.build.finalName}.jar</include>
                        </resource>
                    </resources>
                </configuration>
                <executions>
                    <execution>
                        <phase>install</phase>
                        <goals>
                            <goal>build</goal>
                        </goals>
                    </execution>
                    <execution>
                        <id>tag-image</id>
                        <phase>install</phase>
                        <goals>
                            <goal>tag</goal>
                        </goals>
                        <configuration>
                            <image>${dockerImageUrl}</image>
                            <newName>
                                ${dockerImageUrl}
                            </newName>
                        </configuration>
                    </execution>
                    <execution>
                        <id>push-image</id>
                        <phase>install</phase>
                        <goals>
                            <goal>push</goal>
                        </goals>
                        <configuration>
                            <imageName>
                                ${dockerImageUrl}
                            </imageName>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
```

`jacoco-maven-plugin`插件内容整理：

```xml
            <!-- 代码覆盖率测试 -->
            <plugin>
                <groupId>org.jacoco</groupId>
                <artifactId>jacoco-maven-plugin</artifactId>
                <version>0.8.4</version>
                <executions>
                    <execution>
                        <id>pre-unit-test</id>
                        <goals>
                            <goal>prepare-agent</goal>
                        </goals>
                    </execution>
                    <execution>
                        <id>post-unit-test</id>
                        <phase>test</phase>
                        <goals>
                            <goal>report</goal>
                        </goals>
                    </execution>
                </executions>
            </plugin>
```