#!/bin/bash

CONF="./zeta_cluster.conf"

. $CONF

CURUSER=$(whoami)
SUDO_TEST=$(sudo whoami)


if [ "$CURUSER" != "$IUSER" ]; then
    echo "Must use $IUSER: User: $CURUSER"
fi


HOSTS=$1

if [ "$HOSTS" == "" ]; then
    echo "This script takes a single argument, enclosed by double quotes, of space separated node names to update"
    exit 1
fi

# Make sure we only have one argument, if not, exit
TEST=$2
if [ "$TEST" != "" ]; then
    echo "Please only provide a single argument, enclosed by double quotes, of space separated node names to update"
    exit 1
fi

# Check to see if we are root (by running the $SUDO_TEST)
if [ "$SUDO_TEST" != "root" ]; then
    echo "This script must be run with a user with sudo privileges"
    exit 1
fi

# Iterate through each node specified in the hosts argument and check to see if the user is root or not
echo ""
echo "-------------------------------------------------------------------"
echo "Status of requested Nodes. If root is listed, permissions are setup correctly"
echo "-------------------------------------------------------------------"

CHOSTS=$(echo "$HOSTS"|tr "," " ")

for HOST in $CHOSTS; do
    OUT=$(ssh -t -t -n -o StrictHostKeyChecking=no $HOST "sudo whoami" 2> /dev/null)
    echo "$HOST     $OUT"
done

echo "-------------------------------------------------------------------"
echo ""
echo "If any of the above nodes do not say root next to the name, then the permissions are not set correctly" 
echo "If permissions are not set correctly, this script will not run well."

# Verify that the user wants to continue
read -p "Do you wish to proceed with this script? Y/N: " OURTEST
if [ "$OURTEST" != "Y" ] && [ "$OURTEST" != "y" ]; then
    echo "Exiting"
    exit 0
fi




for HOST in $CHOSTS; do
    echo "Updating and adding cert to $HOST"
    ssh $HOST "sudo rm -f /usr/local/share/ca-certificates/zetaroot.crt && sudo update-ca-certificates -f && sudo curl -o /usr/local/share/ca-certificates/zetaroot.crt http://zetaca-shared.marathon.slave.mesos:10443/cacert && sudo update-ca-certificates && cat /etc/ssl/certs/zetaroot.pem|sudo tee -a /opt/mesosphere/active/python-requests/lib/python3.5/site-packages/requests/cacert.pem"
    echo ""
done


