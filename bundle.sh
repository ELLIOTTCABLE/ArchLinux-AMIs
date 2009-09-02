#!/usr/bin/env bash

AVAILABILITY_ZONE="us-east-1a"

HOST_KEY="ami-bundler"
HOST_GROUP="ami-bundler"

KEY="bundle-testing"
GROUP="bundle-testing"

BUCKET="arch-linux"

if [[ $3 == "x86_64" ]]; then
  HOST_ARCH="x86_64"
  HOST_EC2_ARCH="x86_64"
  HOST_AMI="ami-1b799e72"
  HOST_ITYPE="m1.large"
  ARCH="x86_64"
  EC2_ARCH="x86_64"
  ITYPE="m1.large"
  AKI="aki-b51cf9dc"
  ARI="ari-b31cf9da"
else
  HOST_ARCH="i386"
  HOST_EC2_ARCH="i686"
  HOST_AMI="ami-05799e6c"
  HOST_ITYPE="m1.small"
  ARCH="i386"
  EC2_ARCH="i686"
  ITYPE="m1.small"
  AKI="aki-a71cf9ce"
  ARI="ari-a51cf9cc"
fi

HOST_IID=$(./ami_bundler.sh get $HOST_ARCH) || exit 1

HOST_IADDRESS="(nil)"
while [[ $HOST_IADDRESS == "(nil)" ]]; do
  HOST_IADDRESS=$(ec2-describe-instances --show-empty-fields $HOST_IID \
    | awk '$1 == "INSTANCE" { print $4 }')
done

NAME=$(
	cat "-" "./$2/bundle.sh" <<-SETUP | ssh -o "StrictHostKeyChecking no" -i "id_rsa-$HOST_KEY" root@$HOST_IADDRESS | tail -n1
		source /root/.profile
		
		AVAILABILITY_ZONE="$AVAILABILITY_ZONE"
		KEY="$KEY"
		GROUP="$GROUP"
		BUCKET="$BUCKET"
		HOST_ARCH="$HOST_ARCH"
		HOST_EC2_ARCH="$HOST_EC2_ARCH"
		HOST_AMI="$HOST_AMI"
		HOST_ITYPE="$HOST_ITYPE"
		ARCH="$ARCH"
		EC2_ARCH="$EC2_ARCH"
		ITYPE="$ITYPE"
		AKI="$AKI"
		ARI="$ARI"
	SETUP
)

AMI=$(ec2-register --show-empty-fields "$BUCKET/$NAME.manifest.xml" \
  | awk '/IMAGE/ { print $2 }')

GROUPID=$(ec2-describe-group --show-empty-fields | awk '$1 == "GROUP" \
  && $3 == "'$GROUP'" { print $3 }')
if [[ -z $GROUPID ]]; then
  ec2-add-group --show-empty-fields $GROUP \
    -d "Instances dedicated to bundling AMIs" || exit 1
  ec2-authorize --show-empty-fields $GROUP \
    --protocol tcp --port-range 22 || exit 1
  echo "-- Added security group: $GROUP"
fi

KEYID=$(ec2-describe-keypairs --show-empty-fields \
  | awk '$1 == "KEYPAIR" && $2 == "'$KEY'" { print $2 }')
if [[ -z $KEYID || ! -f "id_rsa-$KEY" ]]; then
  ec2-delete-keypair --show-empty-fields $KEY
  rm -f "id_rsa-$KEY"
  ec2-add-keypair --show-empty-fields $KEY \
    > "id_rsa-$KEY" || exit 1
  chmod 400 "id_rsa-$KEY" || exit 1
  echo "-- Added keypair: $KEY"
fi

IID=$(ec2-run-instances --group $GROUP --key $KEY \
  --availability-zone $AVAILABILITY_ZONE \
  --instance-type $ITYPE $AMI | awk '/INSTANCE/ { print $2 }')
IADDRESS="(nil)"
while [[ $IADDRESS == "(nil)" ]]; do
  IADDRESS=$(ec2-describe-instances --show-empty-fields $IID \
    | awk '$1 == "INSTANCE" { print $4 }')
done

false
until [[ $? == 0 ]]; do
  sleep 5
	ssh -o "StrictHostKeyChecking no" -i "id_rsa-$KEY" root@$IADDRESS <<-ITESTING
		pacman --noconfirm -S sudo wget which vi tar nano lzo2 procinfo \
		  libgcrypt less groff file diffutils dialog dbus-core dash cpio binutils
		
		shutdown -h now && exit
	ITESTING
done

echo "** ${NAME} registered: ${AMI}"

start_host() {
  HOST_GROUPID=$(ec2-describe-group --show-empty-fields | awk '$1 == "GROUP" \
    && $3 == "'$HOST_GROUP'" { print $3 }')
  if [[ -z $HOST_GROUPID ]]; then
    ec2-add-group --show-empty-fields $HOST_GROUP \
      -d "Instances dedicated to bundling AMIs" || exit 1
    ec2-authorize --show-empty-fields $HOST_GROUP \
      --protocol tcp --port-range 22 || exit 1
    echo "-- Added security group: $HOST_GROUP"
  fi
  
  HOST_KEYID=$(ec2-describe-keypairs --show-empty-fields \
    | awk '$1 == "KEYPAIR" && $2 == "'$HOST_KEY'" { print $2 }')
  if [[ -z $HOST_KEYID || ! -f "id_rsa-$HOST_KEY" ]]; then
    ec2-delete-keypair --show-empty-fields $HOST_KEY
    rm -f "id_rsa-$HOST_KEY"
    ec2-add-keypair --show-empty-fields $HOST_KEY \
      > "id_rsa-$HOST_KEY" || exit 1
    chmod 400 "id_rsa-$HOST_KEY" || exit 1
    echo "-- Added keypair: $HOST_KEY"
  fi
  
  HOST_IID=$(ec2-run-instances --show-empty-fields $HOST_AMI \
    --group $HOST_GROUP --key $HOST_KEY --instance-type $HOST_ITYPE \
    --availability-zone $AVAILABILITY_ZONE \
    | awk '$1 == "INSTANCE" { print $2 }') || exit 1
  
  HOST_IADDRESS="(nil)"
  while [[ $HOST_IADDRESS == "(nil)" ]]; do
    HOST_IADDRESS=$(ec2-describe-instances --show-empty-fields $HOST_IID \
      | awk '$1 == "INSTANCE" { print $4 }')
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
  
  echo "** ${HOST_IID}[${HOST_AMI}@${HOST_ITYPE}] launched: ${HOST_IADDRESS}"
}

stop_host() {
  ec2-terminate-instances --show-empty-fields $(get)
  ec2-delete-group --show-empty-fields $HOST_GROUP
  ec2-delete-keypair --show-empty-fields $HOST_KEY
  rm -f "id_rsa-$HOST_KEY"
}

get_host() {
  ec2-describe-instances --show-empty-fields \
    | awk '$1 == "INSTANCE" && $6 == "running" && $7 == "'$HOST_GROUP'" && \
      $10 == "'$HOST_ITYPE'" { print $2; exit }' || exit 1
}

usage() {
  
	cat <<-USAGE
		Usage: `basename $0` <command> [architecture]
		  <command> may be one of (bundle|host)
		  
		  "bundle" expects the following form:
		    `basename $0` bundle <type> [architecture]
		    <type> is any of the folder names in this distribution.
		  
		  "host" expects the following form:
		    `basename $0` host <operation> [architecture]
		    <operation> may be one of (start|stop|restart|get)
		  
		  [architecture] may be one of (i386|x86_64|both). If omitted or any other
		                 value, i386 will be used (this means "i686", "x86", and
		                 "x86_32" are all valid alternatives to "i386", according
		                 to your preference.)
		  
		Notes:
		  If no bundling host is running, than one will be launched before any
		  bundling operation is commenced, and then terminated after the bundling
		  operation. If you plan to bundle more than one type, it’s worth your
		  while to manually start and stop the hosts with the relevant
		  commands, as setup and teardown take quite a while and shouldn’t be
		  repeated where unnecessary.
		  
		Examples:
		  `basename $0` host start
		  `basename $0` host start x86_64
		  `basename $0` bundle Nucleus x86_64
		  `basename $0` bundle Atom
		  `basename $0` host stop x86_64
		  `basename $0` host stop i386
	USAGE
  
  exit 1
}

host() {
  case $2 in
    "restart")  stop_host  "$@"; start_host "$@"  ;;
    "start")    start_host "$@"                   ;;
    "stop")     stop_host  "$@"                   ;;
    "get")      get_host   "$@"                   ;;
    *)          usage      "$@"                   ;;
  esac
  
  exit 1
}

case $1 in
  "bundle") bundle "$@"   ;;
  "host")   host   "$@"   ;;
  *)        usage  "$@"   ;;
esac
