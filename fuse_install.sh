#!/bin/bash


. ./cluster.conf

MEUSER=$(whoami)

if [ "$MEUSER" != "$IUSER" ]; then
    echo "This script needs to be un as $IUSER. Current User: $MEUSER"
    exit 1
fi

if [ ! -f "$PRVKEY" ]; then
    echo "Private does not exist at $PRVKEY"
    echo "Perhaps you need to move the private key to this node?"
    exit 1
fi

if [ ! -f "./ip_detect.sh" ]; then
    echo "ip_detect.sh script not found - Please resolve"
    exit 1
fi




UBUNTU_MAPR_CLIENT_BASE="http://package.mapr.com/releases/v5.1.0/ubuntu/pool/optional/m/mapr-client/"
UBUNTU_MAPR_CLIENT_FILE="mapr-client_5.1.0.37549.GA-1_amd64.deb"
UBUNTU_MAPR_POSIX_BASE="http://package.mapr.com/releases/v5.1.0/ubuntu/pool/optional/m/mapr-posix-client-basic/"
UBUNTU_MAPR_POSIX_FILE="mapr-posix-client-basic_5.1.0.37549.GA-1_amd64.deb"

RH_MAPR_CLIENT_BASE="http://package.mapr.com/releases/v5.1.0/redhat/"
RH_MAPR_CLIENT_FILE="mapr-client-5.1.0.37549.GA-1.x86_64.rpm"
RH_MAPR_POSIX_BASE="http://package.mapr.com/releases/v5.1.0/redhat/"
RH_MAPR_POSIX_FILE="mapr-posix-client-basic-5.1.0.37549.GA-1.x86_64.rpm"

NODE_HOST=$1

if [ "$NODE_HOST" == "" ]; then
    echo "This script must be passed a hostname"
    echo "Exiting"
    exit 0
fi

NETTEST=$(ssh $NODE_HOST hostname)

if [ "$NETTEST" == "" ]; then
    echo "Cannot connect to host"
    exit 1
fi


CONFLIST=$(ssh $NODE_HOST "ls ${MAPR_LIST}/conf/ 2> /dev/null")

if [ "$CONFLIST" != "" ]; then
    echo "Fuse client can not be installed on physical node running the docker container. Please use loopback-nfs"
    exit 1
fi



# Need to update for Cent/RH detection We are only detecting Ubuntu right now
DIST=$(ssh $NODE_HOST "grep DISTRIB_ID /etc/lsb-release")


UBUNTU_CHK=$(echo $DIST|grep Ubuntu)

if [ "$UBUNTU_CHK" != "" ]; then
    INST_DIST="ubuntu"
else
    echo "Cannot detect installation type"
    exit 1
fi

CURCHK=$(ssh $NODE_HOST "ls /opt/mapr 2> /dev/null")

if [ "$CURCHK" != "" ]; then
    echo "Something found in /opt/mapr will not attempt to install"
    exit 1
fi

echo "Installation requested on $NODE_HOST (Ubuntu) - No Previous Installation Detected"
read -p "Continue with install? " -e -i "N" CONT

if [ "$CONT" != "Y" ]; then
    echo "installation aborted"
    exit 0
fi
echo "Installing"

JV=$(ssh $NODE_HOST "grep JAVA_HOME /etc/environment")
if [ "$JV" == "" ]; then
    echo "JAVA_HOME not found in /etc/environment"
    echo "Setting to /opt/mesosphere/active/java/usr/java"
    ssh $NODE_HOST "echo \"JAVA_HOME=/opt/mesosphere/active/java/usr/java\"|sudo tee -a /etc/environment"
fi

mkdir -p ./client_install

if [ "$INST_DIST" == "ubuntu" ]; then
    if [ ! -f "./client_install/$UBUNTU_MAPR_CLIENT_FILE" ] || [ ! -f "./client_install/$UBUNTU_MAPR_POSIX_FILE" ]; then
        echo "Couldn't find MapR Files"
        read -p "Should we Download the Ubuntu files? (Installation will not continue if N) " -e -i "Y" DL
        if [ "$DL" != "Y" ]; then
            echo "Can't continue without installation files"
            exit 1
        fi
        cd ./client_install
        wget ${UBUNTU_MAPR_CLIENT_BASE}${UBUNTU_MAPR_CLIENT_FILE}
        wget ${UBUNTU_MAPR_POSIX_BASE}${UBUNTU_MAPR_POSIX_FILE}
        cd ..
    fi
    INST_CLIENT=$UBUNTU_MAPR_CLIENT_FILE
    INST_POSIX=$UBUNTU_MAPR_POSIX_FILE
    INST_CMD="dpkg -i"
elif [ "$INST_DIST" == "rh" ]; then
    if [ ! -f "./client_install/$RH_MAPR_CLIENT_FILE" ] || [ ! -f "./client_install/$RH_MAPR_POSIX_FILE" ]; then
        echo "Couldn't find MapR Files"
        read -p "Should we Download the RH files? (Installation will not continue if N) " -e -i "Y" DL
        if [ "$DL" != "Y" ]; then
            echo "Can't continue without installation files"
            exit 1
        fi
        cd ./client_install
        wget ${RH_MAPR_CLIENT_BASE}${RH_MAPR_CLIENT_FILE}
        wget ${RH_MAPR_POSIX_BASE}${RH_MAPR_POSIX_FILE}
        cd ..
    fi
    INST_CLIENT=$RH_MAPR_CLIENT_FILE
    INST_POSIX=$RH_MAPR_POSIX_FILE
    INST_CMD="rpm -ivh"
fi

scp ./client_install/$INST_CLIENT $NODE_HOST:/home/$IUSER/
scp ./client_install/$INST_POSIX $NODE_HOST:/home/$IUSER/
ssh $NODE_HOST "sudo $INST_CMD $INST_CLIENT"
NSUB="export MAPR_SUBNETS=$SUBNETS"
ssh $NODE_HOST "sudo sed -i -r \"s@#export MAPR_SUBNETS=.*@${NSUB}@g\" /opt/mapr/conf/env.sh"
ssh $NODE_HOST "echo \"$NODE_HOST-fuse\"|sudo tee /opt/mapr/hostname"
ssh $NODE_HOST "sudo /opt/mapr/server/configure.sh -N $CLUSTERNAME -c -C $CLDBS"
ssh $NODE_HOST "sudo mkdir -p /mapr"
ssh $NODE_HOST "sudo $INST_CMD $INST_POSIX"


tee /tmp/fs_core.xml << EOL1
<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<!--
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License. See accompanying LICENSE file.
-->

<!-- Put site-specific property overrides in this file. -->
<configuration>
  <property>
    <name>fs.mapr.shmpool.size</name>
    <value>0</value>
  </property>
</configuration>
EOL1

scp /tmp/fs_core.xml $NODE_HOST:/home/$IUSER/

rm /tmp/fs_core.xml

CORE_DST="/opt/mapr/hadoop/hadoop-2.7.0/etc/hadoop/core-site.xml"

ssh $NODE_HOST "sudo mv /home/$IUSER/fs_core.xml $CORE_DST && sudo chown mapr:root $CORE_DST && sudo chmod 644 $CORE_DST"

ssh $NODE_HOST "sudo /etc/init.d/mapr-posix-client-basic start"
echo ""
echo "Installed - ls /mapr/$CLUSTERNAME"
echo ""
ssh $NODE_HOST "ls -ls /mapr/$CLUSTERNAME"

