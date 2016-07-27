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


UBUNTU_MAPR_LOOP_BASE="http://package.mapr.com/releases/v5.1.0/ubuntu/pool/optional/m/mapr-loopbacknfs/"
UBUNTU_MAPR_LOOP_FILE="mapr-loopbacknfs_5.1.0.37549.GA-1_amd64.deb"

RH_MAPR_LOOP_BASE="http://package.mapr.com/releases/v5.1.0/redhat/"
RH_MAPR_LOOP_FILE="mapr-loopbacknfs-5.1.0.37549.GA-1.x86_64.rpm"

NODE_HOST=$1
INST_HOME="/usr/local/mapr-loopbacknfs"

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

# Need to update for Cent/RH detection We are only detecting Ubuntu right now
DIST=$(ssh $NODE_HOST "grep DISTRIB_ID /etc/lsb-release")


UBUNTU_CHK=$(echo $DIST|grep Ubuntu)

if [ "$UBUNTU_CHK" != "" ]; then
    INST_DIST="ubuntu"
else
    echo "Cannot detect installation type"
    exit 1
fi

CURCHK=$(ssh $NODE_HOST "ls ${INST_HOME} 2> /dev/null")

if [ "$CURCHK" != "" ]; then
    echo "Something found in ${INST_HOME} will not attempt to install"
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
    if [ ! -f "./client_install/$UBUNTU_MAPR_LOOP_FILE" ]; then
        echo "Couldn't find MapR Files"
        read -p "Should we Download the Ubuntu files? (Installation will not continue if N) " -e -i "Y" DL
        if [ "$DL" != "Y" ]; then
            echo "Can't continue without installation files"
            exit 1
        fi
        cd ./client_install
        wget ${UBUNTU_MAPR_LOOP_BASE}${UBUNTU_MAPR_LOOP_FILE}
        cd ..
    fi
    INST_LOOP=$UBUNTU_MAPR_LOOP_FILE
    INST_CMD="dpkg -i"
    INST_ARP="sudo apt-get install -y nfs-common rpcbind iputils-arping"
elif [ "$INST_DIST" == "rh" ]; then
    if [ ! -f "./client_install/$RH_MAPR_LOOP_FILE" ]; then
        echo "Couldn't find MapR Files"
        read -p "Should we Download the RH files? (Installation will not continue if N) " -e -i "Y" DL
        if [ "$DL" != "Y" ]; then
            echo "Can't continue without installation files"
            exit 1
        fi
        cd ./client_install
        wget ${RH_MAPR_LOOP_BASE}${RH_MAPR_LOOP_FILE}
        cd ..
    fi
    INST_LOOP=$RH_MAPR_LOOP_FILE
    INST_CMD="rpm -ivh"
fi

scp ./client_install/$INST_LOOP $NODE_HOST:/home/$IUSER/
ssh $NODE_HOST "$INST_ARP"
ssh $NODE_HOST "sudo $INST_CMD $INST_LOOP"

NSUB="export MAPR_SUBNETS=$SUBNETS"

ssh $NODE_HOST "echo \"$NSUB\"|sudo tee -a ${INST_HOME}/conf/env.sh"
ssh $NODE_HOST "echo \"export MAPR_HOME=${INST_HOME}\"|sudo tee -a ${INST_HOME}/conf/env.sh"
ssh $NODE_HOST "echo \"$CLUSTERNAME secure=false $CLDBS\"|sudo tee -a ${INST_HOME}/conf/mapr-clusters.conf"
ssh $NODE_HOST "echo \"$NODE_HOST-nfsloop\"|sudo tee ${INST_HOME}/hostname"

ssh $NODE_HOST "sudo mkdir -p /mapr"

ssh $NODE_HOST "sudo /etc/init.d/mapr-loopbacknfs start"

ssh $NODE_HOST "sudo mount -t nfs -o nfsvers=3,noatime,rw,nolock,hard,intr localhost:/mapr /mapr"

echo ""
echo "Installed - ls /mapr/$CLUSTERNAME"
echo ""
ssh $NODE_HOST "ls -ls /mapr/$CLUSTERNAME"

