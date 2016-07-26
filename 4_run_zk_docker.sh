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
    echo "Creating log location on the host"
    ssh $ZK_HOST "sudo mkdir -p ${MAPR_INST}/zookeeper/logs && sudo chown -R mapr:mapr ${MAPR_INST}/zookeeper && sudo chmod 777 ${MAPR_INST}/zookeeper/logs"

    echo "Creating marathon scripts"
    mkdir -p ./zk_marathon

    MFILE="./zk_marathon/mapr_zk_${ZK_HOST}.marathon"

    scp ip_detect.sh ${ZK_HOST}:/home/zetaadm
    ZK_IP=$(ssh ${ZK_HOST} /home/zetaadm/ip_detect.sh)
    echo "$ZK_HOST -> $ZK_IP"

    cat > $MFILE << EOFZK
{
  "id": "mapr/zks/zk${ZK_HOST}",
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
      "image": "${DOCKER_REG_URL}/zkdocker",
      "network": "HOST"
    },
    "volumes": [
      { "containerPath": "/opt/mapr/conf", "hostPath": "${MAPR_INST}/conf", "mode": "RW" },
      { "containerPath": "/opt/mapr/zookeeper/zookeeper-3.4.5/logs", "hostPath": "${MAPR_INST}/zookeeper/logs", "mode": "RW" },
      { "containerPath": "/opt/mapr/zkdata", "hostPath": "${MAPR_INST}/zkdata", "mode": "RW" }
    ]
  }
}
EOFZK


curl -X POST $MARATHON_SUBMIT -d @$MFILE -H "Content-type: application/json"
echo ""
echo ""
done
IFS=$OLDIFS




