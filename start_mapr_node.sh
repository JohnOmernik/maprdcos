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


NODE=$1

CLDB_HOST=$(echo $CLDBS|grep $NODE)

if [ "$CLDB_HOST" != "" ]; then
    echo "This is a CLDB Node"
    MARATHON_FILE="./cldb_marathon/mapr_cldb_${NODE}.marathon"
else
    echo "This is a standard node"
    MARATHON_FILE="./stdnode_marathon/mapr_std_${NODE}.marathon"

fi

echo "Submitting $NODE via $MARATHON_FILE at $MARATHON_SUBMIT"

curl -X POST $MARATHON_SUBMIT -d @$MARATHON_FILE -H "Content-type: application/json"
