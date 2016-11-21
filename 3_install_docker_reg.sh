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

APP_NAME="maprdocker"
APP_CERT_LOC="/opt/maprdocker/dockercerts"
mkdir -p ${APP_CERT_LOC}
sudo chown zetaadm:root ${APP_CERT_LOC}
sudo chmod 770 ${APP_CERT_LOC}
CN_GUESS="maprdocker-mapr-shared.marathon.slave.mesos"

/home/$IUSER/zetaca/gen_server_cert.sh

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
  "env": {
    "REGISTRY_HTTP_TLS_CERTIFICATE": "/certs/srv_cert.pem",
    "REGISTRY_HTTP_TLS_KEY": "/certs/key-no-password.pem"
  },
  "ports": [],
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "zeta/registry:2",
      "network": "BRIDGE",
      "portMappings": [
        { "containerPort": 5000, "hostPort": ${DOCKER_REG_PORT}, "servicePort": 0, "protocol": "tcp"}
      ]
    },
    "volumes": [
      { "containerPath": "/var/lib/registry", "hostPath": "${DOCKER_IMAGE_LOC}", "mode": "RW" },
      { "containerPath": "/certs", "hostPath": "${APP_CERT_LOC}", "mode": "RO" }
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

