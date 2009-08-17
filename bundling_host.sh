#!/usr/bin/env bash

HOST_KEY="bundling-host"
HOST_GROUP="bundling-host"

if [[ $2 == "x86_64" ]]; then
  HOST_ARCH="x86_64"
  HOST_EC2_ARCH="x86_64"
  HOST_AMI="ami-1b799e72"
  HOST_ITYPE="m1.large"
else
  HOST_ARCH="i386"
  HOST_EC2_ARCH="i686"
  HOST_AMI="ami-05799e6c"
  HOST_ITYPE="m1.small"
fi

start() {
  HOST_GROUPID=$(ec2-describe-group | awk '$1 == "GROUP" && $3 == "'$HOST_GROUP'" { print $3 }')
  if [[ -z $HOST_GROUPID ]]; then
    ec2-add-group $HOST_GROUP -d "Instances dedicated to bundling AMIs" || exit 1
    ec2-authorize $HOST_GROUP --protocol tcp --port-range 22 || exit 1
    echo "-- Added security group: $HOST_GROUP"
  fi
  
  HOST_KEYID=$(ec2-describe-keypairs | awk '$1 == "KEYPAIR" && $2 == "'$HOST_KEY'" { print $2 }')
  if [[ -z $HOST_KEYID ]]; then
    ec2-add-keypair $HOST_KEY > "id_rsa-$HOST_KEY" || exit 1
    chmod 400 "id_rsa-$HOST_KEY" || exit 1
    echo "-- Added keypair: $HOST_KEY"
  fi
  
  HOST_IID=$(ec2-run-instances $HOST_AMI --group $HOST_GROUP --key $HOST_KEY \
    --instance-type $HOST_ITYPE | awk '$1 == INSTANCE { print $2 }')  || exit 1
  
  HOST_IADDRESS="pending"
  while [[ $HOST_IADDRESS == "pending" ]]; do
    HOST_IADDRESS=$(ec2-describe-instances $HOST_IID \
      | awk '$1 == INSTANCE { print $4 }')
  done
  
  false
  until [[ $? == 0 ]]; do
    sleep 5
    # TODO: Get rid of these file requirements; take envvars if possible
    scp -o "StrictHostKeyChecking no" -i "id_rsa-$HOST_KEY" \
      ~/.ec2/*.pem \
      ~/.ec2/account_number \
      ~/.ec2/access_key \
      ~/.ec2/secret_key \
      root@$HOST_IADDRESS:/tmp/
  done
  
  case $HOST_ARCH in
  "i386")   EPHEMERAL_STORE='/dev/sda2' ;;
  "x86_64") EPHEMERAL_STORE='/dev/sdb'  ;;
  esac
  
	cat <<-SETUP | ssh -o "StrictHostKeyChecking no" -i "id_rsa-$HOST_KEY" root@$HOST_IADDRESS
		pacman --noconfirm -Syu
		pacman --noconfirm -Syu
		
		pacman --noconfirm -S ruby unzip rsync lzma cpio
		
		pacman --noconfirm -Sc
		
		mount -t ext3 $EPHEMERAL_STORE /mnt
		
		wget http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip
		unzip ec2-ami-tools.zip
		mv ec2-ami-tools-* ec2-ami-tools
		
		cat <<'PROFILE' > /root/.profile
			export EC2_AMITOOL_HOME="\$(pwd)/ec2-ami-tools"
		PROFILE
	SETUP
  
  echo "** ${HOST_IID}[${HOST_AMI}@${HOST_ITYPE}] launched at ${HOST_IADDRESS}"
}

stop() {
  ec2-terminate-instances $(get)
  ec2-delete-group $HOST_GROUP
  ec2-delete-keypair $HOST_KEY
  rm -f "id_rsa-$HOST_KEY"
}

get() {
  ec2-describe-instances --show-empty-fields \
    | awk '$1 == "INSTANCE" && $6 == "running" && $7 == "bundling-host" && \
      $10 == "'$HOST_ITYPE'" { print $2; exit }' || exit 1
}

usage() {
  
	cat <<-USAGE
		Usage: `basename $0` (start|stop|restart|get) [architecture]
		  Architecture may be either "x86_64" or "i386"
	USAGE
  
  exit 1
}

case $1 in
  "restart")  stop; start   ;;
  "start")    start         ;;
  "stop")     stop          ;;
  "get")      get           ;;
  *)          usage         ;;
esac
