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

echo "This script is not functioning at this time"
exit 1

echo "Reconfigure Requested"
echo "It is recommended that you update your cluster.conf and then issue this reconfigure"
echo "Otherwise, a later reconfigure may lose the settings"

TEST_CONF=$(ssh $NODE_HOST "cat $MAPR_INST/conf/mapr-clusters.conf")

if [ "$TEST_CONF" == "" ]; then
    echo "Nothing found in mapr-clusters.conf on $NODE_HOST"
    echo "No reconfigure happening"
fi

ROLES=$(ssh $NODE_HOST "ls -1 $MAPR_INST/roles")


CID=$(ssh $NODE_HOST "sudo docker ps|grep \"\/maprdocker\"|cut -f1 -d\" \"")

echo "---------------------------------------"
echo "Reconfigure requested"
echo ""
echo "NODE_HOST: $NODE_HOST"
echo "Container ID: $CID"
echo "CLUSTERNAME: $CLUSTERNAME"
echo "CLDBS: $CLDBS"
echo "ZKS: $ZKS"
echo "Roles List:"
echo "$ROLES"
echo "---------------------------------------"


MAPR_CONF_OPTS=""


#/opt/mapr/server/configure.sh -C \${CLDBS} -Z \${ZKS} -N \${CLUSTERNAME} -no-autostart \${MAPR_CONF_OPTS}

#/opt/mapr/server/dockerreconf.sh
