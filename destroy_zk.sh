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

NODE_HOST=$1


echo "Are you sure you want to destroy the zk at $NODE_HOST"
echo "This is a bad thing"
read -p "Destroy zk? " -e -i "N" TEST

if [ "$TEST" == "Y" ]; then
    echo "Good luck with that"
    echo "Removing MapR Dirs. If there is things running, it's gonna hork it up"
    ssh $NODE_HOST "sudo rm -rf /opt/mapr/zkdata && sudo rm -rf /opt/mapr/zookeeper"


else
    echo "smart"
    exit 0
fi
