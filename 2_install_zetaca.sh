#!/bin/bash


. ./cluster.conf

ME=$(whoami)
MEHOST=$(hostname)

if [ "$ME" != "$IUSER" ]; then
    echo "This script must be run as the Initial User: $IUSER"
    exit 1
fi

if [ ! -f "./ip_detect.sh" ]; then
    echo "./ip_detect.sh not detected. Please resolve!"
    exit 1
fi
scp ./ip_detect.sh ${ME}@${MEHOST}:/home/${ME}/
MEIP=$(ssh $MEHOST "/home/${ME}/ip_detect.sh")

echo "You are running on $MEHOST ($MEIP) is this where you wish to run the mapr docker registry?"
read -p "Install on $MEHOST - " -e -i "Y" INSTALL_HERE

if [ "$INSTALL_HERE" != "Y" ]; then
    echo "Not installing"
    exit 0
fi


APP_ROOT="/home/$IUSER/zetaca"
APP_HOME="/home/$IUSER/zetaca"

APP_IMG="zeta/zetaca"


BUILD_TMP="./tmp_build"
SOURCE_GIT="https://github.com/JohnOmernik/ca_rest"
DCK=$(sudo docker images|grep zetaca)

if [ "$DCK" == "" ]; then
    BUILD="Y"
else
    echo "The docker image already appears to exist, do you wish to rebuild?"
    echo "$DCK"
    read -e -p "Rebuild Docker Image? " -i "N" BUILD
fi


if [ "$BUILD" == "Y" ]; then
    rm -rf $BUILD_TMP
    mkdir -p $BUILD_TMP
    cd $BUILD_TMP

    if [ "$DOCKER_PROXY" != "" ]; then
        DOCKER_LINE1="ENV http_proxy=$DOCKER_PROXY"
        DOCKER_LINE2="ENV HTTP_PROXY=$DOCKER_PROXY"
        DOCKER_LINE3="ENV https_proxy=$DOCKER_PROXY"
        DOCKER_LINE4="ENV HTTPS_PROXY=$DOCKER_PROXY"
        DOCKER_LINE5="ENV NO_PROXY=$DOCKER_NOPROXY"
        DOCKER_LINE6="ENV no_proxy=$DOCKER_NOPROXY"
    else
        DOCKER_LINE1=""
        DOCKER_LINE2=""
        DOCKER_LINE3=""
        DOCKER_LINE4=""
        DOCKER_LINE5=""
        DOCKER_LINE6=""
    fi

cat > ./Dockerfile << EOF
FROM ubuntu:latest

RUN adduser --disabled-login --gecos '' --uid=2500 zetaadm

$DOCKER_LINE1
$DOCKER_LINE2
$DOCKER_LINE3
$DOCKER_LINE4
$DOCKER_LINE5
$DOCKER_LINE6

RUN gpg --keyserver hkp://pool.sks-keyservers.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
RUN apt-get update && apt-get install -y curl openssl libreadline6 libreadline6-dev zlib1g-dev libssl-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt-dev autoconf libc6-dev ncurses-dev automake libtool bison subversion pkg-config git && rm -rf /var/lib/apt/lis$
RUN \curl -sSL https://get.rvm.io | bash -s stable --ruby
RUN git clone $SOURCE_GIT /root/ca_rest
WORKDIR /root/ca_rest
RUN mkdir -p /root/ca_rest/tmp && chmod 777 /root/ca_rest/tmp
RUN /bin/bash -l -c "rvm requirements"
RUN /bin/bash -l -c "gem install sinatra rest-client"
EXPOSE 80 443
EOF


    sudo docker build -t $APP_IMG .
    cd ..
    rm -rf $BUILD_TMP
else
    echo "Not Building"
fi

if [ -d "$APP_HOME" ]; then
    echo "There is already a CA that exists at the APP_HOME location of $APP_HOME"
    echo "We don't continue, as we don't want you to lose any existing CA information"
    exit 1
fi



mkdir -p $APP_HOME
mkdir -p $APP_HOME/CA
sudo chown -R zetaadm:zetaadm $APP_HOME
sudo chmod 700 $APP_HOME/CA


# Now we will run the docker container to create the CA for Zeta
# Note: Both this script and the git repo script should be changed so we can write the password to a secure file in $APP_HOME/certs/ca_key.txt 
# And the script that instantiates the CA reads the value from the file rather than passing it as an argument that will appear in process listing 

echo ""
read -e -p "Please enter the port for the Zeta CA Rest service to run on: " -i "10443" APP_PORT
echo ""
echo "We need some information for the CA Certificate - You can accept defaults, or choose your own for your setup"
echo "In addition, we may ask if you want to use the CA Certificate value for defaults for other certificates generated, you can always override values on the server certs, but defaults help make things go faster"
echo ""
echo "Remember: "
echo "CA Certificate = The Information on the Certificate for the Certificate Authority"
echo "Default Certificate = A recommened (and overridable) value for use in creating server certificates later"
echo ""
read -e -p "CA Certificate Country (C): " -i "US" CACERT_C
echo ""
read -e -p "Default Certificate Country (C) for generated certificates: " -i $CACERT_C CERT_C
echo ""
read -e -p "CA Certificate State (ST): " -i "WI" CACERT_ST
echo ""
read -e -p "Default Certificate State (ST) for generated certificates: " -i $CACERT_ST CERT_ST
echo ""
read -e -p "CA Certificate Location (L): " -i "Wittenberg" CACERT_L
echo ""
read -e -p "Default Certificate Location (L) for generated certificates: " -i $CACERT_L CERT_L
echo ""
read -e -p "CA Certificate Organization (O): " -i "OIT" CACERT_O
echo ""
read -e -p "Default Certificate Organization (O) for generated certificates: " -i $CACERT_O CERT_O
echo ""
read -e -p "CA Certificate Organizational Unit (OU): " -i "Zeta" CACERT_OU
echo ""
read -e -p "Default Certificate Organizational Unit (OU) for generated certificates: " -i $CACERT_OU CERT_OU
echo ""
read -e -p "CA Certificate Common Name (CN): " -i "marathon.mesos" CERTCA_CN
echo ""
echo "The Common Name for Certificates will be determined at certificate generation"
echo ""
CERT_CN="marathon.mesos"

cat > $APP_HOME/CA/init_ca.sh << EOL1
#!/bin/bash
/root/ca_rest/01_create_ca_files_and_databases.sh /root/ca_rest/CA
EOL1
chmod +x $APP_HOME/CA/init_ca.sh

cat > $APP_HOME/CA/init_all.sh << EOL2
#!/bin/bash
chown -R zetaadm:zetaadm /root
su zetaadm -c /root/ca_rest/CA/init_ca.sh
EOL2
chmod +x $APP_HOME/CA/init_all.sh
sudo docker run -it -e CACERT_C="$CACERT_C" -e CACERT_ST="$CACERT_ST" -e CACERT_L="$CACERT_L" -e CACERT_O="$CACERT_O" -e CACERT_OU="$CACERT_OU" -e CACERT_CN="$CACERT_CN" -v=/${APP_HOME}/CA:/root/ca_rest/CA:rw $APP_IMG /root/ca_rest/CA/init_all.sh

echo "Certs created:"
echo ""
ls -ls $APP_HOME/CA
echo ""
cat > ${APP_HOME}/zetaca_env.sh << EOA
#!/bin/bash
export ZETA_CERT_C="$CERT_C"
export ZETA_CERT_ST="$CERT_ST"
export ZETA_CERT_L="$CERT_L"
export ZETA_CERT_O="$CERT_O"
export ZETA_CERT_OU="$CERT_OU"
export ZETA_CERT_CN="$CERT_CN"
export ZETA_CA_PORT="$APP_PORT"
export ZETA_CA="http://zetaca-shared.marathon.slave.mesos:$APP_PORT"
export ZETA_CA_CERT="\${ZETA_CA}/cacert"
export ZETA_CA_CSR="\${ZETA_CA}/csr"
EOA

cat > $APP_HOME/gen_server_cert.sh << EOSCA
#!/bin/bash
CLUSTERNAME=\$(ls /mapr)
if [ -f "/mapr/$CLUSTERNAME/zeta/kstore/env/zeta_shared.sh" ]; then
    . /mapr/$CLUSTERNAME/zeta/kstore/env/zeta_shared.sh
else
    echo "No Shared Location"
fi

if [ -z "\$APP_NAME" ]; then
    echo "APP_NAME is Not Set using default of Custom"
    APP_NAME="Custom"
fi
if [ -z "\$APP_CERT_LOC" ]; then
    echo "The location to generate the certificates is not set please provide:"
    read -e -p "Path to deposit Certificates: " APP_CERT_LOC
    if [ ! -d "\${APP_CERT_LOC}" ]; then
        echo "The location: \$APP_CERT_LOC doesn't exist, should we create?"
        read -e -p "Create \${APP_CERT_LOC}? " -i "N" CREATE_LOC
        if [ "\$CREATE_LOC" == "Y" ]; then
            mkdir -p \$APP_CERT_LOC
        else
            echo "Exiting"
            exit 1
        fi
    fi
    if [ -f "\${APP_CERT_LOC}/request.csr" ]; then
        echo "A Certificate request already exists there, will not proceed"
        exit 1
    fi
fi
if [ -z "\$CN_GUESS" ]; then
    if [ -z "\${APP_ID}" ] || [ -z "\${APP_ROLE}" ] || [ -z "\${APP_DOMAIN_ROOT}" ]; then
        CN_GUESS="Enter CN for App"
    else
        CN_GUESS="\${APP_ID}-\${APP_ROLE}.\${APP_DOMAIN_ROOT}"
    fi
fi
echo ""
echo "We will now generate a SSL Certificate using ZetaCA"
echo ""
echo ""
read -e -p "\$APP_NAME Certificate Country (C): " -i "\$ZETA_CERT_C" CERT_C
echo ""
read -e -p "\$APP_NAME Certificate State (ST): " -i "\$ZETA_CERT_ST" CERT_ST
echo ""
read -e -p "\$APP_NAME Certificate Location (L): " -i "\$ZETA_CERT_L" CERT_L
echo ""
read -e -p "\$APP_NAME Certificate Organization (O): " -i "\$ZETA_CERT_O" CERT_O
echo ""
read -e -p "\$APP_NAME Certificate Organizational Unit (OU): " -i "\$ZETA_CERT_OU" CERT_OU
echo ""
echo "The suggested CN here is based off the specifics for this app, and it's recommended you use this default or change if you know what you are doing!"
echo ""
read -e -p "\$APP_NAME Certificate Common Name (CN): " -i "\$CN_GUESS" CERT_CN 
echo ""
echo "Generating CA Request"
APP_CERT_REQ="\${APP_CERT_LOC}/request.csr"
APP_CERT_KEY="\${APP_CERT_LOC}/key-no-password.pem"
APP_CERT_SRV="\${APP_CERT_LOC}/srv_cert.pem"
APP_CERT="\${APP_CERT_LOC}/cert.pem"
APP_CERT_SUB="/C=\${CERT_C}/ST=\${CERT_ST}/L=\${CERT_L}/O=\${CERT_O}/OU=\${CERT_OU}/CN=\${CERT_CN}"
APP_CERT_CA="\${APP_CERT_LOC}/cacert.pem"

openssl req -nodes -newkey rsa:2048 -keyout \${APP_CERT_KEY} -out \${APP_CERT_REQ} -subj "\$APP_CERT_SUB"

echo ""
echo "Generating Cert"
curl -o \${APP_CERT_SRV} -F "file=@\${APP_CERT_REQ}" \${ZETA_CA_CSR}
curl -o \${APP_CERT_CA} \${ZETA_CA_CERT}
cat \${APP_CERT_SRV} \${APP_CERT_CA} > \${APP_CERT}
EOSCA
chmod +x ${APP_HOME}/gen_server_cert.sh

cat > ${APP_HOME}/gen_java_keystore.sh << EOJKS
#!/bin/bash
# Now convert to JKS for Drill
CLUSTERNAME=\$(ls /mapr)
. /mapr/\$CLUSTERNAME/zeta/shared/zetaca/gen_server_cert.sh

# Create a single file with both key and cert in pem

APP_KEYCERT_PEM="\${APP_CERT_LOC}/keycert.pem"
APP_CERT_PKCS12="\${APP_CERT_LOC}/keycert.pkcs12"
APP_CERT_CA_DER="\${APP_CERT_LOC}/cacert.crt"

APP_KEYSTORE="\${APP_CERT_LOC}/myKeyStore.jks"
APP_TRUSTSTORE="\${APP_CERT_LOC}/myTrustStore.jts"

APP_KEY_PASS="\${APP_CERT_LOC}/keypass"
APP_TRUST_PASS="\${APP_CERT_LOC}/trustpass"

echo "We need a password for the trust store"
echo ""
echo "***** Note: This password will be echoed on the screen *****"
echo ""
read -e -p "Truststore Password: " TRUSTSTOREPASS
echo ""
echo "We need a password for the key store"
echo ""
echo "***** Note: This password will be echoed on the screen *****"
echo ""
read -e -p "Keystore Password: " KEYSTOREPASS
echo ""
echo -n "\$TRUSTSTOREPASS" > \${APP_TRUST_PASS}
echo -n "\$KEYSTOREPASS" > \${APP_KEY_PASS}


# Cat the Cert and Key together
cat \${APP_CERT_KEY} \${APP_CERT_SRV} \${APP_CERT_CA} > \${APP_KEYCERT_PEM}
# Convert the cacert.pem into der format.
openssl x509 -in \${APP_CERT_CA} -inform pem -out \${APP_CERT_CA_DER} -outform der
# Create the new Trust Store
keytool -import -file \${APP_CERT_CA_DER} -alias mainca -keystore \${APP_TRUSTSTORE} -storepass:file \${APP_TRUST_PASS} -noprompt
# Convert the cert to pkcs12 file
openssl pkcs12 -export -in \${APP_KEYCERT_PEM} -out \${APP_CERT_PKCS12} -name mycert -noiter -nomaciter -passout file:\${APP_KEY_PASS}
# Add Drill Cert to the keystore
keytool -importkeystore -destkeystore \${APP_KEYSTORE} -deststorepass:file \${APP_KEY_PASS} -srckeystore \${APP_CERT_PKCS12} -srcstoretype pkcs12 -srcstorepass:file \${APP_KEY_PASS} -alias mycert
# Add CA Cert to the trust store...
keytool -import -trustcacerts -file \${APP_CERT_CA_DER} -alias mainca -keystore \${APP_KEYSTORE} -storepass:file \${APP_KEY_PASS} -noprompt
rm \${APP_KEY_PASS}
rm \${APP_TRUST_PASS}

cat > \${APP_CERT_LOC}/capass << EOF
#!/bin/bash
export TRUSTSTOREPASS="\$TRUSTSTOREPASS"
export KEYSTOREPASS="\$KEYSTOREPASS"

EOF

EOJKS
chmod +x ${APP_HOME}/gen_java_keystore.sh





cat > ${APP_HOME}/marathon.json << EOL4
{
  "id": "shared/zetaca",
  "cpus": 1,
  "mem": 512,
  "cmd":"/bin/bash -l -c '/root/ca_rest/main.rb'",
  "instances": 1,
  "constraints": [["hostname", "LIKE", "$MEIP"]],
  "env": {
     "SERVER_PORT": "3000",
     "CA_ROOT": "/root/ca_rest/CA"
  },
  "labels": {
   "CONTAINERIZER":"Docker"
  },
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${APP_IMG}",
      "network": "BRIDGE",
      "portMappings": [
        { "containerPort": 3000, "hostPort": ${APP_PORT}, "servicePort": 0, "protocol": "tcp"}
      ]
    },
  "volumes": [
      {
        "containerPath": "/root/ca_rest/CA",
        "hostPath": "${APP_HOME}/CA",
        "mode": "RW"
      }
    ]
  }
}

EOL4
sleep 1

echo "Submitting to Marathon"
curl -X POST $MARATHON_SUBMIT -d @${APP_HOME}/marathon.json -H "Content-type: application/json"
echo ""
echo ""
echo ""
echo ""
echo "Waiting for Zeta CA to start"
sleep 30
echo ""


echo "Updating local certificates on INODES"


MEFULLHOST=$(hostname -f)

TNODES=$(echo -n "$INODES"|tr ";" " ")
for N in $TNODES; do
    NODE=$(echo $N|cut -d":" -f1)
    ./host_zetaca_config.sh $NODE 1
    if [ "$NODE" == "$MEFULLHOST" ]; then
        echo "This was the node that had the Zeta CA Running. We are going to pause 45 seconds for this to restart the zeta ca docker container"
        sleep 45
    fi
done

echo ""
echo ""
echo "This script only updated the agent nodes with the CA information, it's recommend that you run the ./host_zetaca_config.sh script on master nodes as well."
echo ""
echo "To do that, just run: $ ./host_zetaca_config.sh %IPOFMASTERNODE%"
echo ""
echo ""

