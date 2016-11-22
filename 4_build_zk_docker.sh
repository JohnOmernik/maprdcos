#!/bin/bash

. ./cluster.conf

CREDFILE="/home/zetaadm/creds/creds.txt"


VERS_FILE=$1

if [ ! -f "$VERS_FILE" ]; then
    echo "You must pass a version file to this script so it knows what to build"
    echo ""
    echo "Currently Included Versions:"
    echo ""
    ls -ls ./*.vers
    echo ""
    exit 1
fi

. $VERS_FILE

echo "The Version you are asking me to build is $MAPR_VER patch $MAPR_PATCH"
echo "The Docker tag will be $MAPR_DOCKER_TAG"
echo ""
echo "The Deb Repo is: $MAPR_MAIN_URL"
echo "The Ecosystem Repo is: $MAPR_ECOSYSTEM_URL"
echo ""

D_CHK=$(sudo docker images|grep zkdocker|grep $MAPR_DOCKER_TAG)

if [ "$D_CHK" == "" ]; then
    echo "It does NOT appear that version is built at this time"
else
    echo "It does appear that the image you are requesting to build already exist: This is ok"
fi
echo ""

echo "If this information looks correct, you can now choose to build"
read -e -p "Proceed to build (or rebuild) zkdocker:$MAPR_DOCKER_TAG image? " -i "N" BUILD

if [ "$BUILD" != "Y" ]; then
    echo "Not building"
    exit 1
else
    echo "Building"
fi



if [ "$MAPR_PATCH_FILE" != "" ]; then
    DOCKER_PATCH=" && wget ${MAPR_PATCH_ROOT}${MAPR_PATCH_FILE} && dpkg -i $MAPR_PATCH_FILE && rm $MAPR_PATCH_FILE && rm -rf /opt/mapr/.patch"
else
    DOCKER_PATCH=""
fi


if [ ! -f "$CREDFILE" ]; then
    echo "Can't find cred file"
    exit 1
fi

MAPR_CRED=$(cat $CREDFILE|grep "mapr\:")
ZETA_CRED=$(cat $CREDFILE|grep "zetaadm\:")


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

RUN echo "deb $MAPR_MAIN_URL mapr optional" > /etc/apt/sources.list.d/mapr.list

RUN echo "deb $MAPR_ECOSYSTEM_URL binary/" >> /etc/apt/sources.list.d/mapr.list

RUN echo "Name: activate mkhomedir" > /usr/share/pam-configs/my_mkhomedir && echo "Default: yes" >> /usr/share/pam-configs/my_mkhomedir && echo "Priority: 900" >> /usr/share/pam-configs/my_mkhomedir && echo "Session-Type: Additional" >> /usr/share/pam-configs/my_mkhomedir && echo "Session:" >> /usr/share/pam-configs/my_mkhomedir && echo "      required               pam_mkhomedir.so umask=0022 skel=/etc/skel"

RUN echo "base $LDAP_BASE" > /etc/ldap.conf && echo "uri $LDAP_URL" >> /etc/ldap.conf && echo "binddn $LDAP_RO_USER" >> /etc/ldap.conf && echo "bindpw $LDAP_RO_PASS" >> /etc/ldap.conf && echo "ldap_version 3" >> /etc/ldap.conf && echo "pam_password md5" >> /etc/ldap.conf && echo "bind_policy soft" >> /etc/ldap.conf

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -qq -y --allow-unauthenticated mapr-zookeeper mapr-zk-internal libpam-ldap nscd openjdk-8-jre wget perl netcat syslinux-utils${DOCKER_PATCH} && rm -rf /var/lib/apt/lists/* && apt-get clean

RUN DEBIAN_FRONTEND=noninteractive pam-auth-update && sed -i "s/compat/compat ldap/g" /etc/nsswitch.conf && /etc/init.d/nscd restart

RUN usermod -a -G root mapr && usermod -a -G root zetaadm && usermod -a -G adm mapr && usermod -a -G adm zetaadm && usermod -a -G disk mapr && usermod -a -G disk zetaadm

ADD runzkdocker.sh /opt/mapr/

RUN chown -R mapr:mapr /opt/mapr/zookeeper && chown mapr:root /opt/mapr/runzkdocker.sh && chmod 755 /opt/mapr/runzkdocker.sh

CMD ["/bin/bash"]

EOL

cd zkdocker

sudo docker build -t ${DOCKER_REG_URL}/zkdocker:$MAPR_DOCKER_TAG .

cd ..

sudo docker push ${DOCKER_REG_URL}/zkdocker:$MAPR_DOCKER_TAG

rm -rf ./zkdocker

echo "Image pushed and ready to rumble"

