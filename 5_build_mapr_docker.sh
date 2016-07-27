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


cat > ./maprdocker/Dockerfile << EOL
FROM ubuntu:latest

RUN adduser --disabled-login --gecos '' --uid=2500 zetaadm
RUN adduser --disabled-login --gecos '' --uid=2000 mapr

RUN echo "$MAPR_CRED"|chpasswd
RUN echo "$ZETA_CRED"|chpasswd

RUN usermod -a -G root mapr && usermod -a -G root zetaadm && usermod -a -G adm mapr && usermod -a -G adm zetaadm && usermod -a -G disk mapr && usermod -a -G disk zetaadm

RUN echo "deb http://package.mapr.com/releases/v5.1.0/ubuntu/ mapr optional" > /etc/apt/sources.list.d/mapr.list
RUN echo "deb http://package.mapr.com/releases/ecosystem-5.x/ubuntu binary/" >> /etc/apt/sources.list.d/mapr.list

RUN apt-get update && apt-get install -y openjdk-8-jre wget perl netcat nfs-common syslinux-utils 

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
