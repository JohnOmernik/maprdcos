# Running MapR on DCOS
---------------------
This repo allows a (non-standard DCOS) install of MapR running in Docker on a DCOS cluster. 



## Prereqs
---------------------
This assumes some things about your cluster
- DCOS is running and properly configured 
- The nodes have a couple of local users configured
    - zetaadm - UID 2500 (the UID can be changed, it just has to be the same on all nodes)
    - mapr - UID 2000 (the UID can be changed, it just has to be the same on all nodes)
    - There is script included here that will install the users for you (It adds them to the sudoers group and also updates a SSH key for zetaadm user) (zeta_user_prep.sh)
- Docker is installed on all node (This should be done as prereq for the DCOS install)
- I did this on a non-standard Ubuntu 16.04 install of DCOS.  Everything worked, but this is not supported by Mesosphere at this time. 
    - The only thing I updated was a systemd conf file - systemd - edit /etc/systemd/system.conf - set DefaultTasksMax=infinity
    - and updated some links prior to DCOS install: Use Ubuntu at your own risk, however I found CentOS/RH annoying trying to use Overlay FS in Docker
    - Ubuntu Fixes: 
    - sudo ln -s /bin/mkdir /usr/bin/mkdir
    - sudo ln -s /bin/ln /usr/bin/ln
    - sudo ln -s /bin/tar /usr/bin/tar
- In addition to the changes for Ubuntu above, I added a few packages to every node/master. This was in order to help this mapr install
    - sudo apt-get install bc nfs-common syslinux



## Cluster Conf (cluster.conf)
---------------------

This is where the initial configuration of your cluster comes from. It is created by running through the script: 1_create_cluster.conf.sh

## Install Docker Registry
---------------------

I like to run my docker registry ON MapRFS, however, there is no MapRFS when I am installing MapR, thus I create a "bootstrap" Docker Registry to host the MapR Docker images" This is done in 2_install_docker_reg.sh

## Build Zookeeper Image
---------------------
There are two docker images that need to be build. The first is the Zookeeper image.  This is done in 3_build_zk_docker.sh 


