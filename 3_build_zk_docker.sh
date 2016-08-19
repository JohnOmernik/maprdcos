#!/bin/bash

. ./cluster.conf

CREDFILE="/home/zetaadm/creds/creds.txt"


if [ ! -f "$CREDFILE" ]; then
    echo "Can't find cred file"
    exit 1
fi

MAPR_CRED=$(cat $CREDFILE|grep "mapr\:")
ZETA_CRED=$(cat $CREDFILE|grep "zetaadm\:")



sudo docker rmi -f ${DOCKER_REG_URL}/zkdocker

rm -rf ./zkdocker

mkdir ./zkdocker

sudo docker pull ubuntu:latest


cat > ./zkdocker/runzkdocker.sh << EOL3
#!/bin/bash
su -c "/opt/mapr/zookeeper/zookeeper-3.4.5/bin/zkServer.sh start-foreground" mapr
EOL3

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

cat > ./zkdocker/Dockerfile << EOL
FROM ubuntu:latest

$DOCKER_LINE1
$DOCKER_LINE2
$DOCKER_LINE3
$DOCKER_LINE4

RUN adduser --disabled-login --gecos '' --uid=2500 zetaadm
RUN adduser --disabled-login --gecos '' --uid=2000 mapr
RUN echo "$MAPR_CRED"|chpasswd
RUN echo "$ZETA_CRED"|chpasswd

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -qq -y libpam-ldap nscd openjdk-8-jre wget perl netcat syslinux-utils

RUN echo "Name: activate mkhomedir" > /usr/share/pam-configs/my_mkhomedir && echo "Default: yes" >> /usr/share/pam-configs/my_mkhomedir && echo "Priority: 900" >> /usr/share/pam-configs/my_mkhomedir && echo "Session-Type: Additional" >> /usr/share/pam-configs/my_mkhomedir && echo "Session:" >> /usr/share/pam-configs/my_mkhomedir && echo "      required               pam_mkhomedir.so umask=0022 skel=/etc/skel"

RUN echo "base $LDAP_BASE" > /etc/ldap.conf && echo "uri $LDAP_URL" >> /etc/ldap.conf && echo "binddn $LDAP_RO_USER" >> /etc/ldap.conf && echo "bindpw $LDAP_RO_PASS" >> /etc/ldap.conf && echo "ldap_version 3" >> /etc/ldap.conf && echo "pam_password md5" >> /etc/ldap.conf && echo "bind_policy soft" >> /etc/ldap.conf

RUN DEBIAN_FRONTEND=noninteractive pam-auth-update && sed -i "s/compat/compat ldap/g" /etc/nsswitch.conf && /etc/init.d/nscd restart

RUN usermod -a -G root mapr && usermod -a -G root zetaadm && usermod -a -G adm mapr && usermod -a -G adm zetaadm && usermod -a -G disk mapr && usermod -a -G disk zetaadm

RUN wget http://package.mapr.com/releases/v5.1.0/ubuntu/pool/optional/m/mapr-zk-internal/mapr-zk-internal_5.1.0.37549.GA-1_amd64.deb

RUN dpkg -i mapr-zk-internal_5.1.0.37549.GA-1_amd64.deb

ADD runzkdocker.sh /opt/mapr/

RUN chown -R mapr:mapr /opt/mapr/zookeeper && chown mapr:root /opt/mapr/runzkdocker.sh && chmod 755 /opt/mapr/runzkdocker.sh

CMD ["/bin/bash"]

EOL

cd zkdocker

sudo docker build -t ${DOCKER_REG_URL}/zkdocker .

cd ..

sudo docker push ${DOCKER_REG_URL}/zkdocker

rm -rf ./zkdocker

echo "Image pushed and ready to rumble"

