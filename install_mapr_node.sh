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


NODE_HOST=$1

if [ "$NODE_HOST" == "" ]; then
    echo "This script must be passed a hostname and an optional list of disks"
    echo "Exiting"
    exit 0
fi



NODE_DISKS=$2

NETTEST=$(ssh $NODE_HOST hostname)

if [ "$NETTEST" == "" ]; then
    echo "Cannot connect to host"
    exit 1
fi

scp ./ip_detect.sh $NODE_HOST:/home/$IUSER/
ssh $NODE_HOST "chmod +x /home/$IUSER/ip_detect.sh"
NODE_IP=$(ssh $NODE_HOST /home/$IUSER/ip_detect.sh)



echo "Node Host: $NODE_HOST"
echo "Disk List: $NODE_DISKS"
echo "Node ID: $NODE_IP"
echo ""


NODE_TEST=$(ssh $NODE_HOST "sudo cat ${MAPR_INST}/conf/mapr-clusters.conf")

if [ "$NODE_TEST" == "" ]; then
    echo "No mapr-clusters.conf Safe to proceed"
else
    echo "There appears to already be a mapr-clusters.conf on $NODE_HOST"
    echo "The mapr-clusters.conf file has $NODE_TEST in it"
    echo "You may overwrite and blow it away, but likely that will be bad (especially if it's running) This is highly not recommended"
    echo "Do you wish to overwrite? Answering N will cancel this process"
    read -p "Overwrite? " -e -i "N" OW
    if [ "$OW" == "Y" ]; then
        echo "Blowing things away"
        ssh NODE_HOST "sudo rm -rf ${MAPR_INST}/conf/*"
    else
        echo "Smart"
        exit 2
    fi
fi

PARTLIST=$(ssh $NODE_HOST "cat /proc/partitions")

if [ "$NODE_DISKS" == "" ]; then
    echo "No disks were presented to this script"
    echo "You will need to view the output of /proc/partitions, and include the disks you wish to run MapR on"
    echo "This is a destructive process! Any data on these disks will be destroyed"
    echo "Please enter the disks all on the same line, separated only by commas."
    echo ""
    echo "Example: \"/dev/sda,/dev/sdb,/dev/sdc\""
    echo ""
    echo "Output of /proc/partitions"
    echo "$PARTLIST"
    echo ""
    read -p "Disk List: " NODE_DISKS
fi

DISK_CHECK="N"

while [ "$DISK_CHECK" == "N" ]; do

    echo "The following disk list was provided:"
    echo "$NODE_DISKS"
    echo ""
    echo "Please validate this with the output of /proc/partitions"
    echo ""
    echo "$PARTLIST"
    echo ""
    echo "Is $NODE_DISKS correct?"
    read -p "Is the above list correct? (Press E to exit) Y/N/E: " -e -i "N" NTEST
    if [ "$NTEST" == "Y" ]; then
        DISK_CHECK="Y"
    elif [ "$NTEST" == "E" ]; then
        echo "Disk list is not correct and user has given up"
        echo "Exiting"
        exit 3
    else
        echo "You will need to view the output of /proc/partitions, and include the disks you wish to run MapR on"
        echo "This is a destructive process! Any data on these disks will be destroyed"
        echo "Please enter the disks all on the same line, separated only by commas."
        echo ""
        echo "Example: \"/dev/sda,/dev/sdb,/dev/sdc\""
        echo "" 
        echo "Output of /proc/partitions"
        echo "$PARTLIST"
        echo ""
        read -p "Disk List: " NODE_DISKS
        echo ""
        echo ""
    fi
done

echo ""
echo "Copying MapR Defaults to $NODE_HOST"
scp ./mapr_defaults/conf_default.tgz $NODE_HOST:/home/$IUSER/
scp ./mapr_defaults/roles_default.tgz $NODE_HOST:/home/$IUSER/

echo ""
echo "Creating Directories"
ssh $NODE_HOST "sudo mkdir -p ${MAPR_INST}/conf && sudo mkdir -p ${MAPR_INST}/logs && sudo mkdir -p ${MAPR_INST}/roles"

echo ""
echo "Unpacking Defaults"

ssh $NODE_HOST "sudo mv /home/$IUSER/conf_default.tgz ${MAPR_INST}/conf/ && sudo tar zxf ${MAPR_INST}/conf/conf_default.tgz -C ${MAPR_INST}/conf && sudo rm ${MAPR_INST}/conf/conf_default.tgz"

ssh $NODE_HOST "sudo mv /home/$IUSER/roles_default.tgz ${MAPR_INST}/roles/ && sudo tar zxf ${MAPR_INST}/roles/roles_default.tgz -C ${MAPR_INST}/roles && sudo rm ${MAPR_INST}/roles/roles_default.tgz"

echo ""
echo "Updating MAPR_SUBNETS"
NSUB="export MAPR_SUBNETS=$SUBNETS"
ssh $NODE_HOST "sudo sed -i -r \"s@#export MAPR_SUBNETS=.*@${NSUB}@g\" ${MAPR_INST}/conf/env.sh"

echo ""
echo "Updating Warden settings to 35% Max Mem"
ssh $NODE_HOST "sudo sed -i 's/service.command.mfs.heapsize.percent=.*/service.command.mfs.heapsize.percent=25/' ${MAPR_INST}/conf/warden.conf"
ssh $NODE_HOST "sudo sed -i 's/service.command.mfs.heapsize.maxpercent=.*/service.command.mfs.heapsize.maxpercent=35/' ${MAPR_INST}/conf/warden.conf"


echo ""
echo "Copying Disks file"
OLDIFS=$IFS
IFS=","
TFILENAME="${NODE_HOST}_disks.txt"
TFILE="./$TFILENAME"
for DISK in $NODE_DISKS; do
    echo $DISK >> $TFILE
done
IFS=$OLDIFS

scp $TFILE $NODE_HOST:/home/$IUSER/
ssh $NODE_HOST "sudo mv /home/$IUSER/$TFILENAME ${MAPR_INST}/conf/initial_disks.txt"
rm  $TFILE

echo ""
echo "Removing CLDB and Webserver from non control nodes"
CONTROL_CHK=$(echo -n ${CLDBS}|grep ${NODE_HOST})

if [ "$CONTROL_CHK" == "" ]; then
    ssh $NODE_HOST "sudo rm ${MAPR_INST}/roles/cldb"
    ssh $NODE_HOST "sudo rm ${MAPR_INST}/roles/webserver"
    MARFILE="./stdnode_marathon/mapr_std_${NODE_HOST}.marathon"
    MARID="mapr/stdnodes/std${NODE_HOST}"
    MARATHON_CPUS=1
else
    MARFILE="./cldb_marathon/mapr_cldb_${NODE_HOST}.marathon"
    MARID="mapr/cldbs/cldb${NODE_HOST}"
    MARATHON_CPUS=2
fi

NFS_CHK=$(echo -n ${NFS_NODES}|grep ${NODE_HOST})

if [ "$NFS_CHK" == "" ]; then
    ssh $NODE_HOST "sudo rm ${MAPR_INST}/roles/nfs"
fi

echo ""
echo "Updating permissions of directories"
ssh $NODE_HOST "sudo chown -R mapr:mapr ${MAPR_INST}/conf && sudo chown -R mapr:mapr ${MAPR_INST}/logs && sudo chmod -R 755 ${MAPR_INST}/conf && sudo chmod -R 777 ${MAPR_INST}/logs"


echo ""
echo "Getting Memory on Node"

FREECMD="free -m|grep Mem|sed -r \"s/\s{1,}/~/g\"|cut -d\"~\" -f2"
TOTAL_MEM=$(ssh $NODE_HOST $FREECMD)
WARDEN="cat ${MAPR_INST}/conf/warden.conf"

CONTROL_CHK=$(echo -n ${CLDBS}|grep ${NODE_HOST})


ROLES=$(ssh $NODE_HOST "ls -1 ${MAPR_INST}/roles")

MARATHON_MEM=0
FS=$(echo "$ROLES"|grep fileserver)

if [ "$FS" != "" ]; then

    echo "Getting File Server Requirements"
    TMP=$(ssh $NODE_HOST $WARDEN|grep "service\.command\.mfs\.heapsize\.maxpercent="|cut -d'=' -f2)
    TMP1=$(echo -n "0.$TMP")
    MAX_MEM_MB_FLT=$(echo "$TOTAL_MEM * $TMP1"|bc)
    MAX_MEM_MB=$(printf "%1.f\n" $MAX_MEM_MB_FLT)
    MARATHON_MEM=$(echo $MARATHON_MEM + $MAX_MEM_MB|bc)
else
    MAX_MEM_MB=0
fi

NFS=$(echo "$ROLES"|grep nfs)

if [ "$NFS" != "" ]; then
    echo "Getting NFS Server Requirements"
    MAX_NFS=$(ssh $NODE_HOST $WARDEN|grep "service\.command\.nfs\.heapsize\.max="|cut -d'=' -f2)
    MARATHON_MEM=$(echo $MARATHON_MEM + $MAX_NFS|bc)
else
    MAX_NFS=0
fi

WEB=$(echo "$ROLES"|grep webserver)

if [ "$WEB" != "" ]; then 
     echo "Getting Web Server Requirements"
     MAX_WEB=$(ssh $NODE_HOST $WARDEN|grep "service\.command\.webserver\.heapsize\.max="|cut -d'=' -f2)
     MARATHON_MEM=$(echo $MAX_WEB + $MARATHON_MEM|bc)
else
    MAX_WEB=0
fi

CLDB=$(echo "$ROLES"|grep cldb)

if [ "$CLDB" != "" ]; then
    echo "Getting CLDB Requirements"
    MAX_CLDB=$(ssh $NODE_HOST $WARDEN|grep "service\.command\.cldb\.heapsize\.max="|cut -d'=' -f2)
    MARATHON_MEM=$(echo $MARATHON_MEM + $MAX_CLDB|bc)
else
    MAX_CLDB=0
fi

# Add 1000 for the Warden (750 for Warden 250 padding)
MARATHON_MEM=$(echo $MARATHON_MEM + 1000|bc)

echo "Host: $NODE_HOST"
if [ "$CONTROL_CHK" != "" ]; then
    echo "Control Node: True"
else
    echo "Control Node: False"
fi
echo "Total Available Mem: $TOTAL_MEM"
echo "Memory Required for MapR Fileserver: $MAX_MEM_MB"
echo "Memory Required for MapR NFS Server: $MAX_NFS"
echo "Memory Required for MapR Webserver: $MAX_WEB"
echo "Memory Required for MapR CLDB: $MAX_CLDB"
echo "Memory Required for Warden: 1000"
echo "-----------"
echo "Total MapR Mem Required: $MARATHON_MEM"



echo ""
echo "Creating Marathon Files"

mkdir -p ./cldb_marathon
mkdir -p ./stdnode_marathon




cat > $MARFILE << MAREOF
{
  "id": "${MARID}",
  "cpus": ${MARATHON_CPUS},
  "mem": ${MARATHON_MEM},
  "cmd": "/opt/mapr/server/dockerrun.sh",
  "instances": 1,
  "constraints": [["hostname", "LIKE", "$NODE_IP"],["hostname", "UNIQUE"]],
  "labels": {
   "CONTAINERIZER":"Docker"
  },
  "env": {
  "CLDBS": "$CLDBS",
  "MUSER": "$MUSER",
  "ZKS": "$ZKS",
  "CLUSTERNAME": "$CLUSTERNAME",
  "MAPR_CONF_OPTS": "$MAPR_CONF_OPTS"
},
  "ports": [],
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${DOCKER_REG_URL}/maprdocker",
      "privileged": true,
      "network": "HOST"
    },
    "volumes": [
      { "containerPath": "/opt/mapr/conf", "hostPath": "${MAPR_INST}/conf", "mode": "RW" },
      { "containerPath": "/opt/mapr/logs", "hostPath": "${MAPR_INST}/logs", "mode": "RW" },
      { "containerPath": "/opt/mapr/roles", "hostPath": "${MAPR_INST}/roles", "mode": "RW" }
    ]
  }
}
MAREOF




