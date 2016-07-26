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


echo "Are you sure you want to destroy the node at $NODE_HOST"
echo "This is a bad thing"
read -p "Destroy node? " -e -i "N" TEST

if [ "$TEST" == "Y" ]; then
    echo "Good luck with that"
    echo "Removing MapR Dirs. If there is things running, it's gonna hork it up"
    ssh $NODE_HOST "sudo rm -rf /opt/mapr/conf && sudo rm -rf /opt/mapr/logs && sudo rm -rf /opt/mapr/roles"


else
    echo "smart"
    exit 0
fi
