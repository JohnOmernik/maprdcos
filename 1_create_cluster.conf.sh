#!/bin/bash

CONF="./cluster.conf"

if [ -f "$CONF" ]; then
    echo "There already appears to be a conf at $CONF. Please rename or delete and try again"
    exit 0
fi


echo "Let's Create a cluster.conf!"

echo "---------------------------------------"
echo "It's highly recommened your intial user for this is zetaadm. This user should be setup on all nodes, and have passwordless sudo access (preferablly on UID 2500 the default)"
echo "You can change the initial user in the generated config, however the user must have the proper privileges"
echo ""
IUSER="zetaadm"
echo ""
echo "Please pass the path to the private key for the initial user ($IUSER). (This may be located at /home/$IUSER/.ssh/id_rsa, or whereever you may have put it)"
read -p "Path to keyfile: " -e -i "/home/$IUSER/.ssh/id_rsa" IKEY

CURUSER=$(whoami)
if [ "$CURUSER" != "$IUSER" ]; then
    echo "I am sorry, this script must be run as the initial user"
    echo "Initial User: $IUSER"
    echo "Current User: $CURUSER"
    exit 0
fi


echo ""
echo "---------------------------------------"
echo "We are going to create an ip_detect.sh script in this directory."
echo "This may not address your network, so please, review this script and edit prior to step 2"

cat > ./ip_detect.sh << EOFIP
#!/bin/bash
. /etc/profile
INTS="eth0 em1 eno1 enp2s0 enp3s0 ens192"

for INT in \$INTS; do
#    echo "Interface: \$INT"
    T=\$(ip addr|grep "\$INT")
    if [ "\$T" != "" ]; then
        MEIP=\$(ip addr show \$INT | grep -Eo '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
        echo \$MEIP
        break
    fi
done
EOFIP
chmod +x ./ip_detect.sh
echo ""
echo ""
echo ""
echo "*****************************************************"
echo "*** ip_detect.sh script created. Please review!!! ***"
echo "*****************************************************"
echo ""
echo ""
echo ""

echo ""
echo "---------------------------------------"

echo "As we build the docker containers, we need a temporary Docker registry to host the containers"
echo "This is ONLY for mapr based containers" 
echo "It will be named maprdocker-mapr-shared.marathon.slave.mesos by default, only change this name if you understand what that means"
echo "Which host do you wish to run it on?" 
read -p "Docker Registry Host: " -e -i "maprdocker-mapr-shared.marathon.slave.mesos" DOCKER_REG_HOST
read -p "Which port should the docker register run on (we recommend 5000): " -e -i "5000" DOCKER_REG_PORT
echo ""
echo ""
echo "**********************************************************"
echo "You will have to update your docker daemons to accept insecure registries to the above registry."
echo "To this run run the following commands on each node:"
echo ""
echo "sudo mkdir -p /etc/systemd/system/docker.service.d && sudo tee /etc/systemd/system/docker.service.d/override.conf <<- EOF"
echo "[Service]"
echo "ExecStart="
echo "ExecStart=/usr/bin/docker daemon --storage-driver=overlay --insecure-registry=maprdocker-mapr-shared.marathon.slave.mesos:5000 --insecure-registry=dockerregv2-shared.marathon.slave.mesos:5005 -H fd://"
echo "EOF"
echo ""
echo "sudo systemctl daemon-reload"
echo "sudo service docker restart"
echo ""
echo "Now, if you already have override.conf. The key part you need to add to the ExecStart line is:"
echo ""
echo "--insecure-registry=maprdocker-mapr-shared.marathon.slave.mesos:5000 "
echo ""
echo "Then:"
echo "sudo systemctl daemon-reload"
echo "sudo service docker restart"
echo "**********************************************************"
echo ""
echo ""
echo "Information about the MapR versions will be saved in cluster.conf, please review URLS for accuracy"








echo ""
echo "---------------------------------------"
echo "Where would you like the MapR Installtion directory to be location on the physical host?"
echo "It should not be in /opt/mapr to avoid conflicts with clients or other things on the physical node"
read -p "Mapr Installation Directory: " -e -i "/opt/maprdocker" MAPR_INST

#########################
# This is the list of Zookeepers. A few notes, we specify both the zkid and the ports used for leader/quorum elections so they don't conflict with other instances of Zookeeper
# The format here is this: each ZK will be space separated and then for each ZK
# id:hostname:client_port:master_election_port:quorumport
#
# Ideally in the future we will be looking to use exhibitor to create these and just specifying the hosts and client port. For now this is the easiest way to create this. 
# Start your id with 0, MapR really wants you to use 5181 for the client port, and the 2880 and 3880 ports were selected by me to be different from the default of 2888:3888


echo ""
echo "---------------------------------------"
echo "Next step is to identify which nodes will be zookeeper nodes"
echo "The format for this is ZKID:HOSTNAME,ZKID:HOSTNAME"
echo "ZKID: This is the ID the ZK will have. It's an integer, starts at 0"
echo "HOSTNAME: This is obvious. The hostname of the physical node it will be running on"
echo ""
echo "Example: 0:node1,1:node2,2:node3"
echo ""
read -p "Zookeeper String: " ZK_STRING

echo ""
echo "Please enter the client port. I recommend using 5181 the port used by MapR installs"
read -p "ZK Client Port: " -e -i "5181" ZK_CLIENT_PORT
echo ""
echo "Please enter the master election port. Recommend using 2880 as it's different from the normal default for ZK"
read -p "ZK Master Election Port: " -e -i "2880" ZK_MASTER_ELECTION_PORT
echo ""
echo "Please enter the quorum port. Recommend useing 3880 as it's different from the normal default for ZK"
read -p "ZK Quorum Port: " -e -i "3880" ZK_QUORUM_PORT

echo ""
echo "---------------------------------------"
echo "Next we need to understand which nodes will be running CLDB"
echo "Note: All nodes are the real hostnames."
echo "It's recommended to have 3-5 CLDBs running the cluster"
echo "Using the format node:port,node:port,node:port"
echo ""
echo "Example: node1:7222,node2:7222,node3:7222"
echo ""
echo "Use the MapR Default Port of 7222 unless you know what you are doing"
echo ""
read -p "CLDB String: " CLDB_STRING


echo ""
echo "---------------------------------------"
echo "Initial Nodes - These are the initial nodes that are in the cluster"
echo "Nodes can always be added, however, nodes that are running initially must the same or more than the CLDB nodes"
echo "I.e. You need to have at least the CLDB Nodes in this list"
echo ""
echo "The format here is nodename:disk1/disk2/disk3;nodename:/dev/sda,/dev/sdb for that node"
echo ""
echo "Example: node1:/dev/sda,/dev/sdb,/dev/sdc;node2:/dev/sda/dev/sdb"
echo ""
read -p "Enter the initial nodes and their disks: " INITIAL_NODES

echo ""
echo "---------------------------------------"
echo "Please enter the list of nodes that you want to include the NFS Service on."
echo "It should be a CSV list of nodes: node1,node2,node3"
echo ""
read -p "Enter nfs nodes: " NFS_NODES
echo ""

echo ""
echo "---------------------------------------"
echo "If you need to specify a HTTP_PROXY for docker building, please enter it here"
echo "If this variable is filled, it will add the proxy lines to the docker files for building the images"
read -p "Enter the proxy information (blank for none): " DOCKER_PROXY

echo ""
echo "---------------------------------------"
echo "If you need to specify a NO_PROXY string it's highly recommended. Use your subnets and internal domain names"
echo "Example: \"192.168.0.0/16,mycompany.com\""
read -p "Enter the noproxy information (blank for none): " DOCKER_NOPROXY

echo ""
echo "---------------------------------------"
echo "User to run MapR Service as. We recommend mapr with UID 2000 as the default"
read -p "Enter the user for MapR services: " -e -i "mapr" MAPR_USER





echo ""
echo "---------------------------------------"
#########################
# SUBNETS is the value that is replaced in the /opt/mapr/conf/env.sh for MAPR_SUBNETS.  This is important because MapR will try to use the docker interfaces unless you limit this down.  
# You can do commma separated subnets if you have more than one NIC you want to use
#SUBNETS="10.0.2.0/24,10.0.3.0/24"
echo "MapR Allows you to tie your MapR comms to specific subnets.  So if you have two interfaces,and want mapr to use both, specify the IP rangages as subnets to user"
echo "Examples: 10.0.2.0/24,10.0.3.0/24"
read -p "Please specify MapR Subnets: " SUBNETS

echo ""
echo "---------------------------------------"
echo "Please enter the MapR Cluster Name: We recommend it be the same as your DCOS Cluster, but it doesn't have to be"
read -p "Please enter MapR Cluster Name: " CLUSTERNAME

# Put in option to read in MapR Config options

echo ""
echo "---------------------------------------"
echo "Please enter the marathon URL you wish to use (todo: add option for auth)"
echo "Example marathon.mesos:8080"
read -p "Marathon Host: " -e -i "marathon.mesos:8080" MARATHON
echo ""
echo ""

echo ""
echo "---------------------------------------"
echo "We can install LDAP into the MapR Docker containers from the start. We recommend this."
echo "If you choose Y here, we ask you some information about your LDAP env"
echo "You can use an enterprise LDAP here, or you can use the defaults. Once MapR is up and running, we can install open ldap (in the zetadcos repo) for full support"
echo "Do you want to install LDAP?"
read -p "Install LDAP? " -e -i "Y" INSTALL_LDAP

if [ "$INSTALL_LDAP" == "Y" ]; then
    echo "Great, let's check what LDAP YOU want to use"
    echo "Please enter the following information about your LDAP server. Use defaults for a zeta based open ldap server installed after MapR is installed"
    read -p "LDAP URL: " -e -i "ldap://openldap-shared.marathon.slave.mesos" LDAP_URL
    read -p "LDAP Base: " -e -i "dc=marathon,dc=mesos" LDAP_BASE
    read -p "LDAP RO User DN: " -e -i "cn=readonly,dc=marathon,dc=mesos" LDAP_RO_USER
    read -p "LDAP RO User Password: " -e -i "readonly" LDAP_RO_PASS
else
    INSTALL_LDAP="N"
fi

cat > ./cluster.conf << EOF
#!/bin/bash

#########################
# These are the editable settings for installing a MapR running on Docker cluster.  Edit these settings prior to executing the scripts

#########################
# Need a list of nodes we'll be working on. In the future, we will get this auto matically, but for now you have to put a space separated list of the IP address of all nodes in your cluster. 
export INODES="$INITIAL_NODES"

#########################
# IUSER is the initial user to work with. in EC2, this is the AMI user. With the PRVKEY settings, this user should be able to SSH to all hosts in the cluster.
# This could be centos, ubuntu, ec2-user etc. 
export IUSER="$IUSER"

#########################
# PRVKEY is the the key for ssh to all nodes. 
# This is copied to the install host as /home/$IUSER/.ssh/id_rsa
# This is the private key that matches the public key you specified in the AWS install. 
export PRVKEY="$IKEY"

#########################
# Comma separated list of the hostnames for CLDBs. 
# You can include ports (if no port is provided, 7222, the default is used)
# You need at least one. Obviously more is good. If you are not going to run a licensed version of MapR, then 1 is fine.  If you are using M5/M7 put more in a for HA goodness
# Ex:
# CLDBS="host1:7222,host2:7222:host3:7222"
# CLDBS="host1,host2,host3""
# CLDBS="ip-10-22-87-235:7222"
export CLDBS="$CLDB_STRING"

#########################
# This is the location on the physical node that MapR is installed to
# It should be different than the mapr default of /opt/mapr
# It will be mapped to /opt/mapr inside the docker container. 
# It should not be /opt/mapr to keep it out of conflict with anything like mapr client you may install on a node. 
#
export MAPR_INST="$MAPR_INST"

#########################
# This is the docker registry that will be used to house the images so you don't have to build them on every node
# After your cluster is started in AWS, pick a node and use the default port

export DOCKER_REG_HOST="$DOCKER_REG_HOST"
export DOCKER_REG_PORT="$DOCKER_REG_PORT"
export DOCKER_REG_URL="\${DOCKER_REG_HOST}:\${DOCKER_REG_PORT}"
export DOCKER_PROXY="$DOCKER_PROXY"
export DOCKER_NOPROXY="$DOCKER_NOPROXY"


export ZK_STRING="$ZK_STRING"
export ZK_CLIENT_PORT="$ZK_CLIENT_PORT"
export ZK_MASTER_ELECTION_PORT="$ZK_MASTER_ELECTION_PORT"
export ZK_QUORUM_PORT="$ZK_QUORUM_PORT"

export NFS_NODES="$NFS_NODES"
export MAPR_CONF_OPTS=""
export CLUSTERNAME="$CLUSTERNAME"
export SUBNETS="$SUBNETS"
export MUSER="$MAPR_USER"

export MARATHON_HOST="$MARATHON"
export MARATHON_SUBMIT="http://\$MARATHON_HOST/v2/apps"

export INSTALL_LDAP="$INSTALL_LDAP"
export LDAP_BASE="$LDAP_BASE"
export LDAP_URL="$LDAP_URL"
export LDAP_RO_USER="$LDAP_RO_USER"
export LDAP_RO_PASS="$LDAP_RO_PASS"

export MAPR_VER="v5.2.0"
export MAPR_PATCH="39745"

export MAPR_DOCKER_TAG="\${MAPR_VER}-\${MAPR_PATCH}"

export MAPR_MAIN_URL="http://package.mapr.com/releases/v5.2.0/ubuntu/"
export MAPR_ECOSYSTEM_URL="http://package.mapr.com/releases/ecosystem-5.x/ubuntu"


export MAPR_PATCH_ROOT="http://archive.mapr.com/patches/archives/v5.2.0/ubuntu/dists/binary/"

export MAPR_PATCH_FILE="mapr-patch-5.2.0.39122.GA-39745.x86_64.deb"
export MAPR_CLIENT_PATCH_FILE="mapr-patch-client-5.2.0.39122.GA-39745.x86_64.deb"
export MAPR_POSIX_PATCH_FILE="mapr-patch-posix-client-basic-5.2.0.39122.GA-39745.x86_64.deb"
export MAPR_LOOP_PATCH_FILE="mapr-patch-loopbacknfs-5.2.0.39122.GA-39745.x86_64.deb"




########################################################################################################################################################################################################

# Do not change the rest of this script, this creates two more variables from your ZKs, one to put into the zoo.cfg on each ZK (ZOOCFG) and the other to pass to the mapr configure script ($ZKS)


#Example: 0:node1,1:node2,2:node3"

TZKS=""
TZOOCFG=""
OLDIFS=\$IFS
IFS=","

for ZK in \$ZK_STRING; do
    ZID=\$(echo \$ZK|cut -d":" -f1)
    HNAME=\$(echo \$ZK|cut -d":" -f2)

    CPORT=\$ZK_CLIENT_PORT
    QPORT=\$ZK_QUORUM_PORT
    MPORT=\$ZK_MASTER_ELECTION_PORT

    if [ "\$TZKS" != "" ]; then
        TZKS="\${TZKS},"
    fi
    if [ "\$TZOOCFG" != "" ];then
        TZOOCFG="\${TZOOCFG} "
    fi
    TZKS="\${TZKS}\${HNAME}:\${CPORT}"
    TZOOCFG="\${TZOOCFG}server.\${ZID}=\${HNAME}:\${QPORT}:\${MPORT}"
done
IFS=\$OLDIFS
export ZKS=\$TZKS
export ZOOCFG=\$TZOOCFG


EOF

echo "cluster.conf has been creataed!"
