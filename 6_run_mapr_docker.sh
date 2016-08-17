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


if [ ! -f "./install_mapr_node.sh" ]; then
    echo "I can't find the install_mapr_node.sh script. Something is really wrong here"
    exit 1
fi
#DOCKER_REG_HOST=maprdocker.mapr.marathon.mesos
#ZK_STRING=0:zeta2,1:zeta4,2:zeta5
#CLDBS=zeta2:7222,zeta4:7222
#ZK_MASTER_ELECTION_PORT=2880
#INODES=zeta2:/dev/sdc,/dev/sdd,/dev/sde,/dev/sdf;zeta4:/dev/sda,/dev/sdb,/dev/sdc,/dev/sdd,/dev/sde,/dev/sdf,/dev/sdg,/dev/sdh,/dev/sdi,/dev/sdj,/dev/sdk,/dev/sdl
#ZK_CLIENT_PORT=5181
#DOCKER_REG_URL=maprdocker.mapr.marathon.mesos:5000
#ZKS=zeta2:5181,zeta4:5181,zeta5:5181
#MUSER=mapr
#ZOOCFG=server.0=zeta2:3880:2880 server.1=zeta4:3880:2880 server.2=zeta5:3880:2880
#CLUSTERNAME=brewpot
#PRVKEY=/home/zetaadm/.ssh/id_rsa
#SUBNETS=192.168.0.0/24,192.168.200.0/24
#IUSER=zetaadm
#ZK_QUORUM_PORT=3880
#DOCKER_REG_PORT=5000

mkdir -p ./mapr_defaults
mkdir -p ./mapr_defaults/conf
mkdir -p ./mapr_defaults/roles
mkdir -p ./cldb_marathon
mkdir -p ./stdnode_marathon
rm ./mapr_defaults/conf/*
rm ./mapr_defaults/roles/*

if [ ! -f "./mapr_defaults/conf_default.tgz" ] || [ ! -f "./mapr_defaults/roles_default.tgz" ]; then
    echo "Missing roles or conf defaults. Grabbing from a container now"

    CID=$(sudo docker run -d ${DOCKER_REG_URL}/maprdocker sleep 15)

    sudo docker cp ${CID}:/opt/mapr/conf ./mapr_defaults
    sudo docker cp ${CID}:/opt/mapr/roles ./mapr_defaults
    sudo chown zetaadm:zetaadm ./mapr_defaults/conf/*
    sudo chown zetaadm:zetaadm ./mapr_defaults/roles/*

    cd mapr_defaults
    cd conf
    tar zcf ../conf_default.tgz ./*
    cd ..
    cd roles
    tar zcf ../roles_default.tgz ./*
    cd ..
    cd ..
fi

OLDIFS=$IFS
IFS=";"

for NODE in $INODES; do
    NODE_HOST=$(echo $NODE|cut -d":" -f1)
    NODE_DISKS=$(echo $NODE|cut -d":" -f2)
    echo "Node Host: $NODE_HOST"
    echo "Disk List: $NODE_DISKS"
    echo ""
    echo ""
    ./install_mapr_node.sh ${NODE_HOST} ${NODE_DISKS}
    INSTALL_EXIT=$?

    if [ "$INSTALL_EXIT" == "1" ]; then
        echo "Cannot connect to node $NODE_HOST. Exiting"
        exit 1
    elif [ "$INSTALL_EXIT" == "2" ]; then
        echo "Previous install found on node $NODE_HOST"
        echo "Exiting"
        exit 2
    elif [ "$INSTALL_EXIT" == "3" ]; then
        echo "User canceled due to invalid disk list"
        exit 3
    fi
done
IFS=$OLDIFS

echo "Starting CLDB Nodes"
IFS=","

STARTED=""

for CLDB in $CLDBS; do
    CLDB_HOST=$(echo $CLDB|cut -d":" -f1)
    STARTED="$STARTED $CLDB_HOST"

    ./start_mapr_node.sh $CLDB_HOST

done
echo ""
echo ""
echo "Waiting 30 seconds to let the CLDBs Start"
sleep 30

IFS=";"

for NODE in $INODES; do
    NODE_HOST=$(echo $NODE|cut -d":" -f1)
    CHK=$(echo $STARTED|grep $NODE_HOST)
    if [ "$CHK" == "" ]; then
        ./start_mapr_node.sh $NODE_HOST
    fi
done

echo ""
echo ""
IFS=$OLDIFS




