#!/bin/bash

. ./cluster.conf

CREDFILE="/home/zetaadm/creds/creds.txt"

if [ ! -f "$CREDFILE" ]; then
    echo "Can't find cred file"
    exit 1
fi

MAPR_CRED=$(cat $CREDFILE|grep "mapr\:")
ZETA_CRED=$(cat $CREDFILE|grep "zetaadm\:")


rm -rf ./maprdocker

mkdir ./maprdocker

sudo docker rmi -f ${DOCKER_REG_URL}/maprdocker

sudo docker pull ubuntu:latest

cat > ./maprdocker/dockerrun.sh << EOL3
#!/bin/bash
#This is run if there is no disktab in /opt/mapr/conf

service rpcbind start

if [ ! -f "/opt/mapr/conf/mapr-clusters.conf" ]; then
    echo "No mapr-clusters.conf found - Assuming New Install Running Config based on settings"
    /opt/mapr/server/mruuidgen > /opt/mapr/hostid
    cat /opt/mapr/hostid > /opt/mapr/conf/hostid.\$\$
    sed -i 's/AddUdevRules(list/#AddUdevRules(list/' /opt/mapr/server/disksetup

    /opt/mapr/server/configure.sh -C \${CLDBS} -Z \${ZKS} -F /opt/mapr/conf/initial_disks.txt -N \${CLUSTERNAME} -u \${MUSER} -g \${MUSER} -no-autostart \${MAPR_CONF_OPTS}
else
    echo "mapr-clusters.conf found, running warden"
fi

/opt/mapr/server/dockerwarden.sh

EOL3

cat > ./maprdocker/dockerreconf.sh << EOL7
#!/bin/bash

/opt/mapr/server/configure.sh -C \${CLDBS} -Z \${ZKS} -N \${CLUSTERNAME} -no-autostart \${MAPR_CONF_OPTS}

#/opt/mapr/server/dockerrun.sh

EOL7


cat > ./maprdocker/dockerwarden.sh << EOL4
#!/bin/bash
service mapr-warden start

while true
do
sleep 5
done

EOL4

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


cat > ./maprdocker/Dockerfile << EOL
FROM ubuntu:latest

$DOCKER_LINE1
$DOCKER_LINE2
$DOCKER_LINE3
$DOCKER_LINE4

RUN adduser --disabled-login --gecos '' --uid=2500 zetaadm
RUN adduser --disabled-login --gecos '' --uid=2000 mapr

RUN echo "$MAPR_CRED"|chpasswd
RUN echo "$ZETA_CRED"|chpasswd

RUN usermod -a -G root mapr && usermod -a -G root zetaadm && usermod -a -G adm mapr && usermod -a -G adm zetaadm && usermod -a -G disk mapr && usermod -a -G disk zetaadm

RUN echo "deb http://package.mapr.com/releases/v5.1.0/ubuntu/ mapr optional" > /etc/apt/sources.list.d/mapr.list

RUN echo "deb http://package.mapr.com/releases/ecosystem-5.x/ubuntu binary/" >> /etc/apt/sources.list.d/mapr.list

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -qq -y libpam-ldap nscd openjdk-8-jre wget perl netcat syslinux-utils nfs-common

RUN echo "Name: activate mkhomedir" > /usr/share/pam-configs/my_mkhomedir && echo "Default: yes" >> /usr/share/pam-configs/my_mkhomedir && echo "Priority: 900" >> /usr/share/pam-configs/my_mkhomedir && echo "Session-Type: Additional" >> /usr/share/pam-configs/my_mkhomedir && echo "Session:" >> /usr/share/pam-configs/my_mkhomedir && echo "      required               pam_mkhomedir.so umask=0022 skel=/etc/skel"

RUN echo "base $LDAP_BASE" > /etc/ldap.conf && echo "uri $LDAP_URL" >> /etc/ldap.conf && echo "binddn $LDAP_RO_USER" >> /etc/ldap.conf && echo "bindpw $LDAP_RO_PASS" >> /etc/ldap.conf && echo "ldap_version 3" >> /etc/ldap.conf && echo "pam_password md5" >> /etc/ldap.conf && echo "bind_policy soft" >> /etc/ldap.conf

RUN DEBIAN_FRONTEND=noninteractive pam-auth-update && sed -i "s/compat/compat ldap/g" /etc/nsswitch.conf && /etc/init.d/nscd restart

RUN apt-get install -y --allow-unauthenticated mapr-core mapr-core-internal mapr-fileserver mapr-hadoop-core mapr-hbase mapr-mapreduce1 mapr-mapreduce2 mapr-cldb mapr-webserver mapr-nfs

ADD dockerrun.sh /opt/mapr/server/
ADD dockerwarden.sh /opt/mapr/server/
ADD dockerreconf.sh /opt/mapr/server/

RUN chmod +x /opt/mapr/server/dockerrun.sh && chmod +x /opt/mapr/server/dockerwarden.sh && chmod +x /opt/mapr/server/dockerreconf.sh

CMD ["/bin/bash"]

EOL


cd maprdocker

sudo docker build -t ${DOCKER_REG_URL}/maprdocker .
sudo docker push ${DOCKER_REG_URL}/maprdocker

cd ..
rm -rf ./maprdocker
