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


OUT=$(echo $CLDBS|grep $NODE_HOST)

if [ "$OUT" != "" ]; then
    MARID="mapr/cldbs/cldb${NODE_HOST}"
    MARFILE="./cldb_marathon/mapr_cldb_${NODE_HOST}.marathon"
    NTYPE="CLDB"
else
    MARID="mapr/stdnodes/std${NODE_HOST}"
    MARFILE="./stdnode_marathon/mapr_std_${NODE_HOST}.marathon"
    NTYPE="STD"
fi


echo "Are you sure you want to destroy the $NTYPE node at $NODE_HOST"
echo "This is a bad thing"
read -p "Destroy node? " -e -i "N" TEST

if [ "$TEST" == "Y" ]; then
    echo "Good luck with that"
    echo "Removing MapR Dirs. If there is things running, it's gonna hork it up"
    curl -X DELETE ${MARATHON_SUBMIT}/${MARID} -H "Content-type: application/json"
    rm -f ${MARFILE}
    ssh $NODE_HOST "sudo rm -rf ${MAPR_INST}/conf && sudo rm -rf ${MAPR_INST}/logs && sudo rm -rf ${MAPR_INST}/roles"

else
    echo "smart"
    exit 0
fi

