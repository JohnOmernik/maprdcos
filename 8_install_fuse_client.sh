#!/bin/bash

. cluster.conf

echo ""
echo "At this point before you can proceed  to zetadcos, you need to install the fuse client on every node"
echo "Do you wish to do this now?"


NODES=$(echo -n "$INODES"|tr ";" " ")

read -e -p "Auto Install Fuse Client on Agents? " -i "Y" INSTALL

if [ "$INSTALL" != "Y" ]; then
    echo "exiting"
    exit 1
fi

for NODE in $NODES; do
    N=$(echo $NODE|cut -d":" -f1)
    ./fuse_install.sh $N 1
done
echo ""
echo ""
echo ""

echo "Fuse should now be installed on all initial nodes listed in the INODES VARIABLE"
echo "INODES: $INODES"

echo ""
echo ""
echo "All agents need this installed, if the node was not in INODES, then manually install by running:"
echo ""
echo ./fuse_install.sh %INSTALL_NODE%
echo ""
echo ""

