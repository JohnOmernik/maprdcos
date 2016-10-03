#!/bin/bash

. ./cluster.conf

ME=$(whoami)


if [ "$ME" != "$IUSER" ]; then
    echo "This script must be run as the Initial User: $IUSER"
    exit 1
fi

MEHOST=$(hostname)

if [ ! -f "./ip_detect.sh" ]; then
    echo "./ip_detect.sh not detected. Please resolve!"
    exit 1
fi
scp ./ip_detect.sh ${ME}@${MEHOST}:/home/${ME}/
MEIP=$(ssh $MEHOST "/home/${ME}/ip_detect.sh")

echo "You are running on $MEHOST($MEIP) is this where you wish to run the mapr docker registry?"
read -p "Install on $MEHOST - " -e -i "Y" INSTALL_HERE

if [ "$INSTALL_HERE" != "Y" ]; then
    echo "Not installing"
    exit 0
fi

DOCKER_IMAGE_LOC="/opt/maprdocker/images"

sudo mkdir -p ${DOCKER_IMAGE_LOC}

sudo docker pull registry:2
sudo docker tag registry:2 zeta/registry:2

cat > maprdocker.marathon << EOF
{
  "id": "shared/mapr/maprdocker",
  "cpus": 1,
  "mem": 1024,
  "instances": 1,
  "constraints": [["hostname", "LIKE", "$MEIP"]],
  "labels": {
   "CONTAINERIZER":"Docker"
  },
  "ports": [],
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "zeta/registry:2",
      "network": "HOST"
    },
    "volumes": [
      { "containerPath": "/var/lib/registry", "hostPath": "${DOCKER_IMAGE_LOC}", "mode": "RW" }
    ]
  }
}
EOF
echo "Submitting to Marathon"
curl -X POST $MARATHON_SUBMIT -d @maprdocker.marathon -H "Content-type: application/json"
echo ""
echo ""
echo ""
echo ""

