# Running MapR on DCOS
---------------------
This repo allows a (non-standard DCOS) install of MapR running in Docker on a DCOS cluster. 

## Prereqs
---------------------
This assumes some things about your cluster
- DCOS is running and properly configured 
- The nodes with the MapR Fileservers will be run have some attached storage (MapR prefers unformatted, direct attached disks.  These will be dedicated to MapR on the nodes)
- The nodes have a couple of local users configured
    - zetaadm - UID 2500 (the UID can be changed, it just has to be the same on all nodes)
    - mapr - UID 2000 (the UID can be changed, it just has to be the same on all nodes)
    - There is script included here that will install the users for you (It adds them to the sudoers group and also updates a SSH key for zetaadm user) (0_zeta_user_prep.sh)
- Docker is installed on all node (This should be done as prereq for the DCOS install)
    - For this, we recommend making your life easier by setting up some insecure registries upfront. We want to get a cert store going, however at this time, we only have insecure registries. 
    - To do this: on each node, create a file at for docker systemd overrides (this can be done prior to installing Docker):
    - $ sudo mkdir -p /etc/systemd/system/docker.service.d && sudo touch /etc/systemd/system/docker.service.d/override.conf
    - In that file it it should read:
~~~~
[Service]
ExecStart=
ExecStart=/user/bin/docker daemon --storage-driver=overlay --insecure-registry=maprdocker-mapr-shared.marathon.slave.mesos:5000 --insecure-registry=dockerregv2-shared.marathon.slave.mesos:5005 -h fd://
~~~~
- I did this on a non-standard Ubuntu 16.04 install of DCOS.  Everything worked, but this is not supported by Mesosphere at this time. 
    - The only thing I updated was a systemd conf file - systemd - edit /etc/systemd/system.conf - set DefaultTasksMax=infinity
    - and updated some links prior to DCOS install: Use Ubuntu at your own risk, however I found CentOS/RH annoying trying to use Overlay FS in Docker
    - Ubuntu Fixes: 
    - sudo ln -s /bin/mkdir /usr/bin/mkdir
    - sudo ln -s /bin/ln /usr/bin/ln
    - sudo ln -s /bin/tar /usr/bin/tar
- In addition to the changes for Ubuntu above, I added a few packages to every node/master. This was in order to help this mapr install
    - sudo apt-get install bc nfs-common syslinux


## Current Issues:
---------------------
- This is untested.  More work needs to be done to ensure production load capabilities
- MapR does some work to ulimits and other system settings. We need feedback to ensure optimal performance
- Runnnig a mapr-client on the physical node where the server container is running doesn't work. Some odd bugs right now I am tracking down.
  - This means the mapr-fuse client won't work as it relies on the mapr-client. use loopback-nfs instead, that is working on all nodes
- ??? Please report new ones to issues!

# Install Steps

## Create Users
---------------------
MapR and this install needs some users created on all nodes. I recommend installing these users on all nodes, including masters. Use the script 0_zeta_user_prep.sh
Some Notes:
- The script will take a list of nodes and will ask for the password for mapr and zetaaadm and then sync passwords
- The user the script runs as MUST have ssh and sudo permissions on all nodes
- It will create (if one doesn't exist) a ssh key for use on the nodes
- If ran after initial creation it can be used to sync passwords. 

*NOTE: We store the user credentials in plain text in a file at /home/zetaadm/creds/ - We do lock down this directory but be aware - We can discuss options more in an ISSUE 



## Cluster Conf (cluster.conf)
---------------------

This is where the initial configuration of your cluster comes from. It is created by running through the script: 1_create_cluster.conf.sh
Some Notes:
- Right now the IUSER is hardcoded to by zetaadm. This is on purpose. If you think you know what you are doing, and want to take a risk, you can change it yourself. 
- There is a manual step we could improve on. We have to include the docker registry for bootstrap in the docker daemon startup. It's specified in the script. 
- More Docs are needed on this, but I tried to include in the script and comments.  

## Install Docker Registry
---------------------

I like to run my docker registry ON MapRFS, however, there is no MapRFS when I am installing MapR, thus I create a "bootstrap" Docker Registry to host the MapR Docker images" This is done in 2_install_docker_reg.sh
Some Notes:
- This will only have local storage
- We need (todo) to move images from local boot strap to cluster wide registry
- This will be run as mapr/maprdocker 

## Build Zookeeper Image
---------------------
There are two docker images that need to be built. The first is the Zookeeper image.  This is done in 3_build_zk_docker.sh 
Some Notes:
- This should be pretty basic
- It will pull ubuntu:latest prior (if you don't have this)
- This docker build does display the credentials for the mapr user and zetaadm user.  I will work on an issue to discuss the best way to handle this

## Run Zookeeper
---------------------
Once built, the Zookeepers will be started. This happens here: 4_run_zk_docker.sh
Some Notes:
- As will all things, each individual ZK will be given it's own marathon application. For ZK it will be under mapr/zks/.  The instance will be both unique and tied to a host so you can't scale beyond one instance
- Local storage will be used for zkdata and logs. This will be in the MAPR_INST variable. Since we want things to run on the same node, this works well
- We should look at moving the conf directory to be local storage. It will make updating the conf easier down the line (add todo)

## Build MapR Docker Image
---------------------
We need to build the mapr docker image. This is done in 5_build_mapr_docker.sh 
Some Notes:
- This is a large image. (2.15 GB) We may try to make this smaller, but it shoudn't matter much. 

## Run MapR Docker
---------------------
Where the cluster gets built. 6_run_mapr_docker.sh to read conf and then run install_mapr_node.sh on each node
Some Notes:
- Will base install the nodes in inodes in the conf.
- You can add more ndoes with the install_mapr_node.sh script
- Will show the disk for each node, you need to confirm or change. 
- Local storage is used on each node for logs, conf, and roles
- Each instance will get it's own marathon app under mapr/cldbs or mapr/stdnodes
- You will need to license your own mapr follow the links to do so. 

## Fuse Client Install/Uninstall
---------------------
fuse_install.sh and fuse_remove.sh to add or remove a fuse_client. 
Some Notes:
- It will mount at /mapr/$CLUSTERNAME
- It's licensed, only 10 are allowed with base M3 license
- Ask your mapr Rep for more license if needed
- Will not work with physical nodes that are hosting docker containers. Working on that bug. Use loopback nfs instead. 

## Loopback-nfs Client Install/Uninstall
---------------------
loop_install.sh and loop_remove.sh will add or remove a loopback nfs client.
- It will mount at /mapr/$CLUSTERNAME
- It's licensed, only 10 are allowed with base M3 license
- Ask your mapr Rep for more license if needed

## destroy_node.sh and destroy_zk.sh
---------------------
These scripts remove the local storage to start from scratch. 
Some Notes:
- Does stop and destroy the app in marathon as well. 
- If it fails try the fully qualified name (it has to be what ever is in the cldb, zk, initial node string) 


