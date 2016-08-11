#!/bin/bash

. ./cluster.conf

CREDFILE="/home/zetaadm/creds/creds.txt"


if [ ! -f "$CREDFILE" ]; then
    echo "Can't find cred file"
    exit 1
fi

MAPR_CRED=$(cat $CREDFILE|grep "mapr\:")
ZETA_CRED=$(cat $CREDFILE|grep "zetaadm\:")

sudo docker rmi -f ${DOCKER_REG_URL}/maprclientbase

rm -rf ./maprclientbase

mkdir ./maprclientbase


if [ "$DOCKER_PROXY" != "" ]; then
    DOCKER_LINE1="ENV http_proxy=$DOCKER_PROXY"
    DOCKER_LINE2="ENV HTTP_PROXY=$DOCKER_PROXY"
    DOCKER_LINE3="ENV https_proxy=$DOCKER_PROXY"
    DOCKER_LINE4="ENV HTTPS_PROXY=$DOCKER_PROXY"
else
    DOCKER_LINE1=""
    DOCKER_LINE2=""
    DOCKER_LINE3=""
    DOCKER_LINE4=""
fi

cat > ./maprclientbase/Dockerfile << EOL
FROM ubuntu:latest

$DOCKER_LINE1
$DOCKER_LINE2
$DOCKER_LINE3
$DOCKER_LINE4

RUN adduser --disabled-login --gecos '' --uid=2500 zetaadm 
RUN adduser --disabled-login --gecos '' --uid=2000 mapr
RUN echo "$MAPR_CRED"|chpasswd
RUN echo "$ZETA_CRED"|chpasswd

RUN groupadd --gid 2501 zetausers && usermod -a -G zetausers mapr && usermod -a -G zetausers zetaadm

RUN usermod -a -G root mapr && usermod -a -G root zetaadm && usermod -a -G adm mapr && usermod -a -G adm zetaadm && usermod -a -G disk mapr && usermod -a -G disk zetaadm

RUN echo "deb http://package.mapr.com/releases/v5.1.0/ubuntu/ mapr optional" > /etc/apt/sources.list.d/mapr.list
RUN echo "deb http://package.mapr.com/releases/ecosystem-5.x/ubuntu binary/" >> /etc/apt/sources.list.d/mapr.list

RUN apt-get update && apt-get install -y openjdk-8-jre wget perl netcat syslinux-utils && apt-get install -y --allow-unauthenticated mapr-client && apt-get clean -y && apt-get autoclean -y && rm -rf /var/lib/apt/lists/*

RUN /opt/mapr/server/configure.sh -C ${CLDBS} -Z ${ZKS} -N ${CLUSTERNAME}

CMD ["/bin/bash"]

EOL

cd maprclientbase

sudo docker build -t ${DOCKER_REG_URL}/maprclientbase .

cd ..

sudo docker push ${DOCKER_REG_URL}/maprclientbase

rm -rf ./maprclientbase

echo "Image pushed and ready to rumble"

