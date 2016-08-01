#!/bin/bash

###################
# Purpose of this script
# 1.Check to make sure the user we are running on has sudo
# 2. Get the current user
# 3. Update sudoers to not require a tty (like ubunutu)
# 3. Get the password for
# 1. Change and sync all mapr user passwords on all nodes
# 2. Create zetaadm user on all nodes with synced password
# 3. Ensure zetaadm is in the sudoers group on all nodes
# 4. Create zetaadm home volume in MapR-FS
# 5. Create ssh keypair for zetaadm - private in home volume, ensure public is in authorized_keys on all nodes


SUDO_TEST=$(sudo whoami)
IUSER=$(whoami)

ZETA_ID="2500"
MAPR_ID="2000"

HOSTS=$1

# Make sure that we have a list of hosts to use, if not, exit
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
for HOST in $HOSTS; do
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


# Ask the user for the passwords for the mapr and zetaadm users
echo ""
echo "--------------------------------------------------"
####################
###### ADD zetaadm user and sync passwords on mapr User
echo "Prior to installing Zeta, there are two steps that must be taken to ensure two users exist and are in sync across the nodes"
echo "The two users are:"
echo ""
echo "mapr - This user is installed by the mapr installer and used for mapr services, however, we need to change the password and sync the password across the nodes"
echo "zetaadm - This is the user you can use to administrate your cluster and install packages etc."
echo ""
echo "Please keep track of these users' passwords"
echo ""
echo ""
# TODO: remove this first question and rely on the while statement to ask the questions
echo "Syncing mapr password on all nodes"
stty -echo
printf "Please enter new password for mapr user on all nodes: "
read mapr_PASS1
echo ""
printf "Please re-enter password for mapr: "
read mapr_PASS2
echo ""
stty echo

# If the passwords don't match, keep asking for passwords until they do
while [ "$mapr_PASS1" != "$mapr_PASS2" ]
do
    echo "Passwords entered for mapr user do not match, please try again"
    stty -echo
    printf "Please enter new password for mapr user on all nodes: "
    read mapr_PASS1
    echo ""
    printf "Please re-enter password for mapr: "
    read mapr_PASS2
    echo ""
    stty echo
done

# TODO: remove this first question and rely on the while statement to ask the questions
echo ""
echo "Adding user zetaadm to all nodes"
stty -echo
printf "Please enter the zetaadm Password: "
read zetaadm_PASS1
echo ""

printf "Please re-enter the zetaadm Password: "
read zetaadm_PASS2
echo ""
stty echo

# If the passwords don't match, keep asking for passwords until they do
while [ "$zetaadm_PASS1" != "$zetaadm_PASS2" ]
do
    echo "Passwords for zetaadm do not match, please try again"
    echo ""
    stty -echo
    printf "Please enter the zetaadm Password: "
    read zetaadm_PASS1
    echo ""

    printf "Please re-enter the zetaadm Password: "
    read zetaadm_PASS2
    echo ""
    stty echo
done


# TODO: Do we want any user to be able to do passwordless sudo? Maybe just the current user?
echo ""
echo "Updating Sudoers to not require TTY per Ubuntu"
for HOST in $HOSTS; do
  ssh -t -t -n -o StrictHostKeyChecking=no $HOST "sudo sed -i \"s/Defaults    requiretty//g\" /etc/sudoers"
  ssh -t -t -n -o StrictHostKeyChecking=no $HOST "sudo sed -i \"s/Defaults   \!visiblepw//g\" /etc/sudoers"
done

# Create the script that will be executed on each machine to add the users
echo ""
echo "Creating User Update Script"

SCRIPT="/tmp/userupdate.sh"
SCRIPTSRC="/home/$IUSER/userupdate.sh"
cat > $SCRIPTSRC << EOF
#!/bin/bash
DIST_CHK=\$(egrep -i -ho 'ubuntu|redhat|centos' /etc/*-release | awk '{print toupper(\$0)}' | sort -u)
UB_CHK=\$(echo \$DIST_CHK|grep UBUNTU)
RH_CHK=\$(echo \$DIST_CHK|grep REDHAT)
CO_CHK=\$(echo \$DIST_CHK|grep CENTOS)

if [ "\$UB_CHK" != "" ]; then
    INST_TYPE="ubuntu"
    echo "Ubuntu"
elif [ "\$RH_CHK" != "" ] || [ "\$CO_CHK" != "" ]; then
    INST_TYPE="rh_centos"
    echo "Redhat"
else
    echo "Unknown lsb_release -a version at this time only ubuntu, centos, and redhat is supported"
    echo \$DIST_CHK
    exit 1
fi

echo "\$INST_TYPE"

if [ "\$INST_TYPE" == "ubuntu" ]; then
   adduser --disabled-login --gecos '' --uid=$ZETA_ID zetaadm
   adduser --disabled-login --gecos '' --uid=$MAPR_ID mapr
   echo "zetaadm:$zetaadm_PASS1"|chpasswd
   echo "mapr:$mapr_PASS1"|chpasswd
elif [ "\$INST_TYPE" == "rh_centos" ]; then
   adduser --uid $ZETA_ID zetaadm
   adduser --uid $MAPR_ID mapr
   echo "$zetaadm_PASS1"|passwd --stdin zetaadm
   echo "$mapr_PASS1"|passwd --stdin mapr
else
    echo "Relase not found, not sure why we are here, exiting"
    exit 1
fi
Z=\$(sudo grep zetaadm /etc/sudoers)
M=\$(sudo grep mapr /etc/sudoers)

if [ "\$Z" == "" ]; then
    echo "Adding zetaadm to sudoers"
    echo "zetaadm ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi
if [ "\$M" == "" ]; then
    echo "Adding mapr to sudoers"
    echo "mapr ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi
EOF
chmod 700 $SCRIPTSRC

# Copy the script over to each node and execute it, removing it after the work is done
# TODO: Verify that the script worked on each node?
echo "Creating Users"
for HOST in $HOSTS; do
  scp -o StrictHostKeyChecking=no $SCRIPTSRC $HOST:$SCRIPT
  ssh -o StrictHostKeyChecking=no $HOST "chmod 700 $SCRIPT"
  ssh -o StrictHostKeyChecking=no $HOST "sudo $SCRIPT"
  ssh -o StrictHostKeyChecking=no $HOST "sudo rm $SCRIPT"
done
rm $SCRIPTSRC

####################
# Saving creds for later
# TODO: Change how this is stored/handled
echo "Saving Creds"
sudo mkdir -p /home/zetaadm/creds

cat > /home/${IUSER}/creds.txt << EOC
zetaadm:${zetaadm_PASS1}
mapr:${mapr_PASS1}
EOC


sudo mv /home/${IUSER}/creds.txt /home/zetaadm/creds/
sudo chown -R zetaadm:zetaadm /home/zetaadm/creds
sudo chmod -R 700 /home/zetaadm/creds

PUBLOC="/home/zetaadm/.ssh/id_rsa.pub"
PRIVLOC="/home/zetaadm/.ssh/id_rsa"


echo "Creating Keys"

CREATE=1

PRIVT=$(sudo cat $PRIVLOC)
PUBT=$(sudo cat $PUBLOC)


if [ "$PRIVT" != "" ]; then
    if [ "$PUBT" != "" ]; then
        echo "$PRIVLOC and $PUBLOC already exists, do you wish us to recreate it? If No, we will copy the old id_rsa.pub to the hosts in this run"
        read -p "Create new id_rsa key pair? Y for new, N to reuse old: " -e -i "N" NEWPAIR
        if [ "$NEWPAIR" == "N" ]; then
            CREATE=0
        fi
    else
        echo "$PRIVLOC found on this node, but $PUBLOC not found. Will cowardly refuse to create new keypair"
        exit 0
    fi
fi

sudo mkdir -p /home/zetaadm/.ssh
sudo chown zetaadm:zetaadm /home/zetaadm/.ssh

if [ "$CREATE" == "1" ]; then
    TMPPUB="/tmp/id_rsa.pub"
    TMPPRIV="/tmp/id_rsa"
    ssh-keygen -f $TMPPRIV -N ""

    chmod 700 $TMPPRIV
    chmod 700 $TMPPUB

    sudo mv $TMPPRIV /home/zetaadm/.ssh/
    sudo mv $TMPPUB /home/zetaadm/.ssh/
    sudo chown zetaadm:zetaadm $PRIVLOC
    sudo chown zetaadm:zetaadm $PUBLOC
fi

PUB=$(sudo cat $PUBLOC)

# Add the keys on each node
for HOST in $HOSTS; do
    echo "Updating Authorized Keys on $HOST"
    ssh -o StrictHostKeyChecking=no $HOST "sudo mkdir -p /home/zetaadm/.ssh && echo \"$PUB\"|sudo tee -a /home/zetaadm/.ssh/authorized_keys && sudo chown -R zetaadm:zetaadm /home/zetaadm/.ssh && sudo chmod 700 /home/zetaadm/.ssh && sudo chmod 600 /home/zetaadm/.ssh/authorized_keys"
done




