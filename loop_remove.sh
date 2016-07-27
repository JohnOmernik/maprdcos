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

INST_HOME="/usr/local/mapr-loopbacknfs"

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

# Need to update for Cent/RH detection We are only detecting Ubuntu right now
DIST=$(ssh $NODE_HOST "grep DISTRIB_ID /etc/lsb-release")


UBUNTU_CHK=$(echo $DIST|grep Ubuntu)

if [ "$UBUNTU_CHK" != "" ]; then
    INST_DIST="ubuntu"
else
    echo "Cannot detect installation type"
    exit 1
fi

CURCHK=$(ssh $NODE_HOST "ls  ${INST_HOME}/ 2> /dev/null")

if [ "$CURCHK" == "" ]; then
    echo "Loopback Install Not found"
    exit 1
fi

echo "Loopback nfs Removal requested on $NODE_HOST ($INST_DIST) - Previous Installation Detected"
read -p "Continue with Removal? " -e -i "N" CONT

if [ "$CONT" != "Y" ]; then
    echo "installation aborted"
    exit 0
fi
echo "Removing"


if [ "$INST_DIST" == "ubuntu" ]; then
    REM_LOOP="mapr-loopbacknfs"
    REM_CMD="dpkg --purge --force-all"
elif [ "$INST_DIST" == "rh" ]; then
    REM_LOOP=""
    REM_CMD=""
fi



ssh $NODE_HOST "sudo umount /mapr"
ssh $NODE_HOST "sudo /etc/init.d/mapr-loopbacknfs stop"
ssh $NODE_HOST "sudo $REM_CMD $REM_LOOP"


echo ""
echo "Removed from $NODE_HOST"
echo ""

