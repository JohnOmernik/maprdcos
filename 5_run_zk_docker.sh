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

IPDETECT_TEST=$(./ip_detect.sh)

if [ "$IPDETECT_TEST" == "" ]; then
    echo "It appears that eh ip_detect.sh located at /home/$IUSER didn't return anything for this node"
    echo "It should likely be updated if you want the MapR installation to succeed"
    echo "It should return the IP address of the primary interface on this cluster."
else
    echo "The ip_detect.sh script returned $IPDETECT_TEST"
    echo "This should be the IP for the primary interface on this node, but it should work on all nodes the same way"
    echo "If you are unsure if this is the case, exit here, and test on all nodes"
fi

echo ""
echo "Based on the results of the ip_detect.sh, do you wish to go on?"
read -e -p "Do the ip_detect.sh results look accurate? " -i "N" IPTEST

if [ "$IPTEST" != "Y" ]; then
    echo "Exiting due to ip_detect results"
    exit 1
fi

mkdir -p ./mapr_defaults
mkdir -p ./mapr_defaults/conf
mkdir -p ./zk_marathon
rm ./mapr_defaults/conf/*

if [ ! -f "./mapr_defaults/zk_default.tgz" ]; then
    echo "Missing zk defaults. Grabbing from a container now"

    CID=$(sudo docker run -d ${DOCKER_REG_URL}/zkdocker:${MAPR_DOCKER_TAG} sleep 15)

    sudo docker cp ${CID}:/opt/mapr/zookeeper/zookeeper-3.4.5/conf ./mapr_defaults
    sudo chown zetaadm:zetaadm ./mapr_defaults/conf/*

    cd mapr_defaults
    cd conf
    tar zcf ../zk_default.tgz ./*
    cd ..
    cd ..
fi

OLDIFS=$IFS
IFS=","

for ZK in $ZK_STRING; do
    ZK_ID=$(echo $ZK|cut -d":" -f1)
    ZK_HOST=$(echo $ZK|cut -d":" -f2)
    echo "ID: $ZK_ID"
    echo "Host: $ZK_HOST"
    echo ""
    ZKTEST=$(ssh $ZK_HOST "sudo cat ${MAPR_INST}/zkdata/myid 2> /dev/null")
    if [ "$ZKTEST" == "" ]; then
        echo "No myid Safe to proceed"
    else
        echo "There appears to already be a zookeeper myid for $ZK_HOST"
        echo "The myid file has $ZKTEST in it"
        echo "You may overwrite and blow it away, but likely that will be bad (especially if it's running)"
        echo "Do you wish to overwrite? Answering N will cancel this process"
        read -p "Overwrite? " -e -i "N" OW
        if [ "$OW" == "Y" ]; then
            echo "Blowing things away"
            ssh $ZK_HOST "sudo rm -rf ${MAPR_INST}/zkdata"
        else
            echo "Smart"
            exit 0
        fi
    fi
    echo ""
done
IFS=$OLDIFS



echo "Creating zoo.cfg"
ZKOUT=$(echo -n $ZOOCFG|tr " " "\n")
tee ./zk_marathon/zoo.cfg << EOL1
# The number of milliseconds of each tick
tickTime=2000
# The number of ticks that the initial
# synchronization phase can take
initLimit=20
# The number of ticks that can pass between
# sending a request and getting an acknowledgement
syncLimit=10
# the directory where the snapshot is stored.
dataDir=/opt/mapr/zkdata
# the port at which the clients will connect
clientPort=$ZK_CLIENT_PORT
# max number of client connections
maxClientCnxns=100
#autopurge interval - 24 hours
autopurge.purgeInterval=24
#superuser to allow zk nodes delete
superUser=$MUSER
#readuser to allow read zk info for authenticated clients
readUser=anyone
# cldb key location
mapr.cldbkeyfile.location=/opt/mapr/conf/cldb.key
#security provider name
authMech=SIMPLE-SECURITY
# security auth provider
authProvider.1=org.apache.zookeeper.server.auth.SASLAuthenticationProvider
# use maprserverticket not userticket for auth
mapr.usemaprserverticket=true
$ZKOUT
EOL1



echo "Ok, setting up the data locations on each node"
IFS=","
for ZK in $ZK_STRING; do
    ZK_ID=$(echo $ZK|cut -d":" -f1)
    ZK_HOST=$(echo $ZK|cut -d":" -f2)
    echo "ID: $ZK_ID"
    echo "Host: $ZK_HOST"
    echo ""
    echo "Creating MapR Conf Dir if it doesn't exist"
    ssh $ZK_HOST "sudo mkdir -p ${MAPR_INST}/conf && sudo chown mapr:mapr ${MAPR_INST}/conf && sudo chmod 755 ${MAPR_INST}/conf"
    echo "Creating zkdata location and setting myid"
    ssh $ZK_HOST "sudo mkdir -p ${MAPR_INST}/zkdata && echo $ZK_ID|sudo tee ${MAPR_INST}/zkdata/myid && sudo chown -R mapr:mapr ${MAPR_INST}/zkdata && sudo chmod 750 ${MAPR_INST}/zkdata"
    echo "Creating ZK conf and log location on the host"
    ssh $ZK_HOST "sudo mkdir -p ${MAPR_INST}/zookeeper/logs && sudo mkdir -p ${MAPR_INST}/zookeeper/conf"

    echo "Copying zk defaults and cfg to $ZK_HOST"
    scp ./mapr_defaults/zk_default.tgz $ZK_HOST:/home/$IUSER/
    scp ./zk_marathon/zoo.cfg $ZK_HOST:/home/$IUSER/

    echo ""
    echo "Unpacking and copying conf"
    ssh $ZK_HOST "sudo mv /home/$IUSER/zk_default.tgz ${MAPR_INST}/zookeeper/conf/ && sudo tar zxf ${MAPR_INST}/zookeeper/conf/zk_default.tgz -C ${MAPR_INST}/zookeeper/conf && sudo rm ${MAPR_INST}/zookeeper/conf/zk_default.tgz"
    ssh $ZK_HOST "sudo mv /home/$IUSER/zoo.cfg ${MAPR_INST}/zookeeper/conf/"
    ssh $ZK_HOST "sudo chown -R mapr:mapr ${MAPR_INST}/zookeeper && sudo chmod 777 ${MAPR_INST}/zookeeper/logs"


    echo "Creating marathon scripts"

    MFILE="./zk_marathon/mapr_zk_${ZK_HOST}.marathon"

    scp ip_detect.sh ${ZK_HOST}:/home/zetaadm
    ZK_IP=$(ssh ${ZK_HOST} /home/zetaadm/ip_detect.sh)
    echo "$ZK_HOST -> $ZK_IP"

    cat > $MFILE << EOFZK
{
  "id": "shared/mapr/zks/zk${ZK_HOST}",
  "cpus": 1,
  "mem": 1536,
  "cmd": "/opt/mapr/runzkdocker.sh",
  "instances": 1,
  "constraints": [["hostname", "LIKE", "$ZK_IP"],["hostname", "UNIQUE"]],
  "labels": {
   "CONTAINERIZER":"Docker"
  },
  "env": {
  "ZOO_LOG4J_PROP": "INFO,ROLLINGFILE",
  "ZOO_LOG_DIR": "/opt/mapr/zookeeper/zookeeper-3.4.5/logs"
},
  "ports": [],
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${DOCKER_REG_URL}/zkdocker:${MAPR_DOCKER_TAG}",
      "network": "HOST"
    },
    "volumes": [
      { "containerPath": "/opt/mapr/conf", "hostPath": "${MAPR_INST}/conf", "mode": "RW" },
      { "containerPath": "/opt/mapr/zookeeper/zookeeper-3.4.5/logs", "hostPath": "${MAPR_INST}/zookeeper/logs", "mode": "RW" },
      { "containerPath": "/opt/mapr/zookeeper/zookeeper-3.4.5/conf", "hostPath": "${MAPR_INST}/zookeeper/conf", "mode": "RW" },
      { "containerPath": "/opt/mapr/zkdata", "hostPath": "${MAPR_INST}/zkdata", "mode": "RW" },
      { "containerPath": "/etc/localtime", "hostPath": "/etc/localtime", "mode": "RO"}
    ]
  }
}
EOFZK


curl -X POST $MARATHON_SUBMIT -d @$MFILE -H "Content-type: application/json"
echo ""
echo ""
done
IFS=$OLDIFS




