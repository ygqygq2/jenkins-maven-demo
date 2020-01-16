FROM openjdk:8-jdk-alpine

LABEL maintainer "29ygq@sina.com"

ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$JAVA_HOME/lib:/data/lib

ARG JAR_FILE
ADD ${JAR_FILE} /myservice.jar

ENTRYPOINT ["java", "-Duser.timezone=GMT+08", "-Djava.security.egd=file:/dev/./urandom", "-jar", "/myservice.jar"]
