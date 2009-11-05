#!/usr/bin/env bash

AVAILABILITY_ZONE="us-east-1a"

HOST_GROUP="__bundling-host__"
HOST_KEY=$HOST_GROUP

GROUP="__ami-testing__"
KEY=$GROUP

BUCKET="arch-linux"

usage() {
  
	cat <<-USAGE
		Usage: `basename $0` <command> [architecture]
		  <command> may be one of (bundle|host)
		  
		  "bundle" expects the following form:
		    `basename $0` bundle <type> [architecture]
		    <type> is any of the folder names in this distribution.
		  
		  "host" expects the following form:
		    `basename $0` host <operation> [architecture]
		    <operation> may be one of (setup|start|stop|restart|teardown|get)
		  
		  [architecture] may be one of (i686|x86_64|all). If omitted, defaults to
		    operating on all.
		  
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
		  `basename $0` bundle Nucleus i686
		  `basename $0` bundle Atom
		  `basename $0` host stop all
	USAGE
  
  exit 1
}

# ================
# = AMI bundling =
# ================

bundle() {
  TYPE="$2"
  if [[ ! -d "$TYPE" ]]; then usage "$@"; fi
  
  echo "== Preparing EC2 environment"
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
  
  STARTED_HOST=''
  HOST_IID=$($0 host get $HOST_ARCH)
  if [[ -z $HOST_IID ]]; then
    echo "== No bundling host exists, instantiating one"
    STARTED_HOST='yes'
    host_setup "$@" || exit 1
    host_start "$@" || exit 1
  fi
  
  HOST_IADDRESS=$(ec2-describe-instances --show-empty-fields $HOST_IID \
    | awk '$1 == "INSTANCE" { print $4 }')
  
  echo "== Uploading elements to bundling host"
  scp -qrp -o "StrictHostKeyChecking no" -i "id_rsa-$HOST_KEY" \
    "./$TYPE" \
    root@$HOST_IADDRESS:/tmp/
  
  echo "== Connecting to bundling host"
  NAME=$(
		cat "-" "./$TYPE/bundle.sh" <<-SETUP | ssh -o "StrictHostKeyChecking no" -i "id_rsa-$HOST_KEY" root@$HOST_IADDRESS | tail -n1
			echo "-- Preparing bundling host"
			source /root/.profile
			
			ELEMENTS="/tmp/$TYPE"
			
			AVAILABILITY_ZONE="$AVAILABILITY_ZONE"
			HOST_GROUP="$HOST_GROUP"
			HOST_KEY="$HOST_KEY"
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
			echo "-- Executing \\\`$TYPE/bundle.sh\\\` on the bundling host"
		SETUP
  )
  
  echo "== Registering $NAME as an AMI"
  AMI=$(ec2-register --show-empty-fields "$BUCKET/$NAME.manifest.xml" \
    | awk '/IMAGE/ { print $2 }')
  
  echo "== Instantiating $AMI to test"
  IID=$(ec2-run-instances --group $GROUP --key $KEY \
    --availability-zone $AVAILABILITY_ZONE \
    --instance-type $ITYPE $AMI | awk '/INSTANCE/ { print $2 }')
  IADDRESS="(nil)"
  while [[ $IADDRESS == "(nil)" ]]; do
    IADDRESS=$(ec2-describe-instances --show-empty-fields $IID \
      | awk '$1 == "INSTANCE" { print $4 }')
  done
  
  echo "== Connecting to testing instance"
  false
  until [[ $? == 0 ]]; do
    sleep 5
		ssh -o "StrictHostKeyChecking no" -i "id_rsa-$KEY" root@$IADDRESS <<-'ITESTING'
			echo "?? uname: `uname --all`"
			echo "-- Installing packages with pacman"
			pacman --noconfirm -S sudo wget which vi tar nano lzo2 procinfo \
			  libgcrypt less groff file diffutils dialog dbus-core dash cpio binutils
			
			INSTALL_STATUS=$?
			shutdown -h now && exit $INSTALL_STATUS
		ITESTING
  done
  
  if [[ -n $STARTED_HOST ]]; then
    echo "-- Terminating the bundling host we launched"
    STARTED_HOST=''
    host_stop     "$@" || exit 1
    host_teardown "$@" || exit 1
  fi
  
  echo "** ${NAME} registered: ${AMI}"
}

# ============================
# = Bundling host management =
# ============================

host() {
  case $2 in
    "setup")    host_setup    "$@" || exit 1                                ;;
    "teardown") host_teardown "$@" || exit 1                                ;;
    "restart")  host_stop     "$@" || exit 1; host_teardown "$@" || exit 1  
                host_setup    "$@" || exit 1; host_start    "$@" || exit 1  ;;
    "start")    host_setup    "$@" || exit 1; host_start    "$@" || exit 1  ;;
    "stop")     host_stop     "$@" || exit 1; host_teardown "$@" || exit 1  ;;
    "get")      host_get      "$@" || exit 1                                ;;
    *)          usage         "$@"                                          ;;
  esac
}

host_setup() {
  echo "== Preparing EC2 environment for bundling host"
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
}

host_teardown() {
  HOST_IIDS=$(ec2-describe-instances --show-empty-fields \
    | awk '$1 == "INSTANCE" && $7 == "'$HOST_GROUP'" && \
      $6 != "terminated" { print $6 }')
  if [[ -z $HOST_IIDS ]]; then
    echo "-- There are no active bundling hosts, wiping groups and keys"
    ec2-delete-group --show-empty-fields $HOST_GROUP
    ec2-delete-keypair --show-empty-fields $HOST_KEY && \
      rm -f "id_rsa-$HOST_KEY"
    
    ec2-delete-group --show-empty-fields $GROUP
    ec2-delete-keypair --show-empty-fields $KEY && \
      rm -f "id_rsa-$KEY"
  fi
}

host_start() {
  echo "== Launching bundling host"
  HOST_IID=$(ec2-run-instances --show-empty-fields $HOST_AMI \
    --group $HOST_GROUP --key $HOST_KEY --instance-type $HOST_ITYPE \
    --availability-zone $AVAILABILITY_ZONE \
    | awk '$1 == "INSTANCE" { print $2 }') || exit 1
  
  HOST_IADDRESS="(nil)"
  while [[ $HOST_IADDRESS == "(nil)" ]]; do
    HOST_IADDRESS=$(ec2-describe-instances --show-empty-fields $HOST_IID \
      | awk '$1 == "INSTANCE" { print $4 }')
  done
  
  echo "== Uploading keys to bundling host"
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
  "i686")   EPHEMERAL_STORE='/dev/sda2' ;;
  "x86_64") EPHEMERAL_STORE='/dev/sdb'  ;;
  esac
  
  echo "== Connecting to bundling host"
	cat <<-SETUP | ssh -o "StrictHostKeyChecking no" -i "id_rsa-$HOST_KEY" root@$HOST_IADDRESS
		echo "== Preparing host for bundling operations"
		cd /tmp
		mount -t ext3 "$EPHEMERAL_STORE" /mnt
		
		echo "-- Constructing pacman mirrorlist"
		wget -O mirrorlist "http://repos.archlinux.org/wsvn/packages/pacman-mirrorlist/repos/core-$HOST_ARCH/mirrorlist?op=dl&rev=0"
		# TODO: Use the API endpoint to leave in the European mirrors if appropriate
		cat mirrorlist | awk '\$1 == "#" { \
		  if(\$0 ~ "United States") {foo = 1} else {foo = 0} }; \
		  {if(foo == 1) print }' | \
		  sed -r 's/^#(Server)/\1/' | sed 's/@carch@/$HOST_ARCH/' \
		  > mirrorlist.regional
		
		wget -O bruenig-rankmirrors.tar.gz "http://github.com/bruenig/rankmirrors/tarball/25c28fd69785db6e83aee789e97134e1e3edfaa7"
		tar -xzf bruenig-rankmirrors.tar.gz
		./bruenig-rankmirrors-*/rankmirrors -v mirrorlist.regional \
		  > mirrorlist.ranked
		
		cp -p mirrorlist.ranked /etc/pacman.d/mirrorlist
		
		echo "-- Updating software on bundling host"
		pacman --noconfirm -Syu
		pacman --noconfirm -Syu
		
		pacman --noconfirm -S unzip rsync lzma cpio
		
		# FIXME: This will *have* to be updated with the ARM2 conversion is done
		pacman --noconfirm -U http://arm.kh.nu/old/extra/os/$HOST_ARCH/ruby-1.8.7_p174-1-$HOST_ARCH.pkg.tar.gz
		
		pacman --noconfirm -Sc
		
		echo "-- Installing EC2 AMI tools"
		wget -q http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip
		unzip -oq ec2-ami-tools.zip
		mv ec2-ami-tools-* /mnt/ec2-ami-tools
		
		cat <<'PROFILE' > /root/.profile
			export EC2_AMITOOL_HOME="/mnt/ec2-ami-tools"
		PROFILE
	SETUP
  
  echo "** ${HOST_IID}[${HOST_AMI}@${HOST_ITYPE}] launched: ${HOST_IADDRESS}"
}

host_stop() {
  echo "== Terminating the $HOST_ARCH bundling host"
  IID=$(host_get "$@")
  if [[ -n $IID ]]; then
    ec2-terminate-instances --show-empty-fields $IID
    echo "-- Waiting for the host to shut down"
    STATUS="running"
    while [[ $STATUS != "terminated" ]]; do
      STATUS=$(ec2-describe-instances $IID --show-empty-fields \
        | awk '$1 == "INSTANCE" { print $6 }')
    done
  fi
  
  true
}

host_get() {
  ec2-describe-instances --show-empty-fields \
    | awk '$1 == "INSTANCE" && $6 == "running" && $7 == "'$HOST_GROUP'" && \
      $10 == "'$HOST_ITYPE'" { print $2; exit }' || exit 1
}

# ====================
# = Argument parsing =
# ====================

case $3 in
  "32"|"x86"|"i386"|"i686")
    HOST_ARCH="i686"
    HOST_EC2_ARCH="i386"
    HOST_AMI="ami-05799e6c"
    HOST_ITYPE="m1.small"
    ARCH="i686"
    EC2_ARCH="i386"
    ITYPE="m1.small"
    AKI="aki-841efeed"
    ARI="ari-9a1efef3"
  ;;
  "64"|"x64"|"x86_64"|"x86-64"|"amd64")
    HOST_ARCH="x86_64"
    HOST_EC2_ARCH="x86_64"
    HOST_AMI="ami-1b799e72"
    HOST_ITYPE="m1.large"
    ARCH="x86_64"
    EC2_ARCH="x86_64"
    ITYPE="m1.large"
    AKI="aki-9c1efef5"
    ARI="ari-901efef9"
  ;;
  ""|"all")
    echo "==  i686  =="
    $0 $1 $2 'i686' || exit $?
    echo "== x86_64 =="
    $0 $1 $2 'x86_64' || exit $?
    exit 0
  ;;
  *) usage "$@" ;;
esac

case $1 in
  "bundle") bundle "$@"   ;;
  "host")   host   "$@"   ;;
  *)        usage  "$@"   ;;
esac
