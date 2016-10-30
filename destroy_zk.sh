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
SHINY=$2

MFILE="./zk_marathon/mapr_zk_${NODE_HOST}.marathon"
MID="shared/mapr/zks/zk${NODE_HOST}"


if [ "$SHINY" == "" ]; then
    echo "Are you sure you want to destroy the zk at $NODE_HOST"
    echo "This is a bad thing"
    read -p "Destroy zk? " -e -i "N" TEST
elif [ "$SHINY" == "YEP" ]; then
    TEST="Y"
else
  echo "I'm sorry, you need more SEKRIT"
  TEST="N"
fi



if [ "$TEST" == "Y" ]; then
    echo "Good luck with that"
    echo "Removing MapR Dirs. If there is things running, it's gonna hork it up"
    ssh $NODE_HOST "sudo rm -rf ${MAPR_INST}/zkdata && sudo rm -rf ${MAPR_INST}/zookeeper"
    curl -X DELETE ${MARATHON_SUBMIT}/${MID} -H "Content-type: application/json"
    rm -f $MFILE

else
    echo "smart"
    exit 0
fi
