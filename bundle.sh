#!/usr/bin/env bash

HOST_AVAILABILITY_ZONE="us-east-1a"

BUNDLING_HOST_GROUP="__bundling-host__"
BUNDLING_HOST_KEY=$BUNDLING_HOST_GROUP

KERNEL_HOST_GROUP="__kernel-host__"
KERNEL_HOST_KEY=$KERNEL_HOST_GROUP

TEST_GROUP="__ami-testing__"
TEST_KEY=$TEST_GROUP

BUCKET="arch-linux"

if [[ -z $EC2_HOME ]]; then EC2_HOME="$HOME/.ec2"; fi
if [[ -z $EC2_PRIVATE_KEY ]]; then
  EC2_PRIVATE_KEY=$($(which ls) "$EC2_HOME/pk-*.pem"); fi
if [[ -z $EC2_CERT ]]; then
  EC2_CERT=$($(which ls) "$EC2_HOME/cert-*.pem"); fi

if [[ -z $AWS_ACCOUNT_NUMBER ]]; then
  AWS_ACCOUNT_NUMBER="$(cat $EC2_HOME/account_number)"; fi
if [[ -z $S3_ACCESS_KEY ]]; then
  S3_ACCESS_KEY="$(cat $EC2_HOME/access_key)"; fi
if [[ -z $S3_SECRET_KEY ]]; then
  S3_SECRET_KEY="$(cat $EC2_HOME/SECRET_KEY)"; fi

_usage() {
  
	cat <<-USAGE
		Usage: `basename $0` <command> <argument> [architecture] [options]
		  <command> may be one of (bundle|test|host).
		  
		  "bundle" expects the following form:
		    `basename $0` bundle <type> [architecture]
		    <type> is any of the folder names in this distribution.
		    [options] may include --public.
		  
		  "test" expects one of the following forms:
		    `basename $0` test <AMI-ID> [architecture]
		    `basename $0` test <operation> [architecture]
		    <operation> may be one of (setup|teardown). If anything else is
		    provided, it will be treated as an AMI ID to be tested.
		  
		  "host" expects the following form:
		    `basename $0` host <operation> [architecture]
		    <operation> may be one of (setup|start|stop|restart|teardown|get).
		  
		  [architecture] may be one of (i686|x86_64|all). If omitted, defaults to
		    operating on all.
		  
		Notes:
		  If no bundling host is running, than one will be launched before any
		  bundling operation is commenced, and then terminated after the bundling
		  operation. If you plan to bundle more than one type, it’s worth your
		  while to manually start and stop the hosts with the relevant
		  commands, as setup and teardown take quite a while and shouldn’t be
		  repeated where unnecessary. The same applies to the kernel host, and
		  testing environment setup/teardown.
		  
		ENV variables:
		  This tool expects a few environment variables to be configured:
		    
		    EC2_HOME: Directory containing your EC2 tools and certificates
		    EC2_PRIVATE_KEY: Absolute path to your EC2 X.509 private key file
		    EC2_CERT: Absolute path to your EC2 X.509 certificate
		    
		    AWS_ACCOUNT_NUMBER: Your numerical AWS account number (i.e.
		      3161-7741-1691—will be read from $EC2_HOME/account_number
		      if undefined)
		    S3_ACCESS_KEY: Your S3 access key (will be read from
		      $EC2_HOME/access_key if undefined)
		    S3_SECRET_KEY: Your S3 secret access key (will be read from
		      $EC2_HOME/secret_key if undefined)
		  
		Usage examples:
		  `basename $0` host start
		  `basename $0` host setup x86_64
		  `basename $0` bundle Nucleus i686
		  `basename $0` bundle Atom
		  `basename $0` test ami-18ab99
		  `basename $0` host stop all
	USAGE
  
  exit 1
}

if [[ -z $1 || -z $2 ]]; then
  _usage "$@"
fi

if [[ -z $EC2_PRIVATE_KEY || -z $EC2_CERT || -z $AWS_ACCOUNT_NUMBER
   || -z $S3_ACCESS_KEY || -z $S3_SECRET_KEY ]]; then
  echo "!! FATAL: Missing environment variables or certificate files"
  _usage "$@"
fi

# ================
# = AMI bundling =
# ================

_bundle() {
  TYPE="$2"
  if [[ ! -d "$TYPE" ]]; then usage "$@"; fi
  
  TAG=$(git describe --exact-match HEAD 2>/dev/null || git rev-parse --short HEAD)
  
  STARTED_BUNDLING_HOST=''
  BUNDLING_HOST_IID=$(host_get "$@")
  if [[ -z $BUNDLING_HOST_IID ]]; then
    echo "== No bundling host exists, instantiating one"
    STARTED_BUNDLING_HOST='yes'
    host_setup "$@" || exit 1
    host_start "$@" || exit 1
  fi
  
  BUNDLING_HOST_IADDRESS=$(ec2-describe-instances --show-empty-fields $BUNDLING_HOST_IID \
    | awk '$1 == "INSTANCE" { print $4 }')
  
  echo "== Uploading elements to bundling host"
  scp -qrp -o "StrictHostKeyChecking no" -i "id_rsa-$BUNDLING_HOST_KEY" \
    "./$TYPE" \
    "./README.markdown" \
    root@$BUNDLING_HOST_IADDRESS:/tmp/
  
  echo "== Connecting to bundling host"
  NAME=$(
		cat "-" "./$TYPE/bundle.sh" <<-SETUP | ssh -o "StrictHostKeyChecking no" -i "id_rsa-$BUNDLING_HOST_KEY" root@$BUNDLING_HOST_IADDRESS | tail -n1
			echo "-- Preparing bundling host"
			source /root/.profile
			
			TAG="$TAG"
			TYPE="$TYPE"
			ELEMENTS="/tmp/$TYPE"
			
			EC2_HOME="$EC2_HOME"
			EC2_PRIVATE_KEY="$EC2_PRIVATE_KEY"
			EC2_CERT="$EC2_CERT"
			AWS_ACCOUNT_NUMBER="$AWS_ACCOUNT_NUMBER"
			S3_ACCESS_KEY="$S3_ACCESS_KEY"
			S3_SECRET_KEY="$S3_SECRET_KEY"
			
			HOST_AVAILABILITY_ZONE="$HOST_AVAILABILITY_ZONE"
			BUNDLING_HOST_GROUP="$BUNDLING_HOST_GROUP"
			BUNDLING_HOST_KEY="$BUNDLING_HOST_KEY"
			KERNEL_HOST_GROUP="$KERNEL_HOST_GROUP"
			KERNEL_HOST_KEY="$KERNEL_HOST_KEY"
			TEST_KEY="$TEST_KEY"
			TEST_GROUP="$TEST_GROUP"
			BUCKET="$BUCKET"
			BUNDLING_HOST_ARCH="$BUNDLING_HOST_ARCH"
			BUNDLING_HOST_EC2_ARCH="$BUNDLING_HOST_EC2_ARCH"
			BUNDLING_HOST_AMI="$BUNDLING_HOST_AMI"
			BUNDLING_HOST_ITYPE="$BUNDLING_HOST_ITYPE"
			ARCH="$ARCH"
			EC2_ARCH="$EC2_ARCH"
			TEST_ITYPE="$TEST_ITYPE"
			KERNEL_ARCH="$KERNEL_ARCH"
			KERNEL_HOST_AMI="$KERNEL_HOST_AMI"
			KERNEL_HOST_ARCH="$KERNEL_HOST_ARCH"
			KERNEL_HOST_EC2_ARCH="$KERNEL_HOST_EC2_ARCH"
			KERNEL_HOST_ITYPE="$KERNEL_HOST_ITYPE"
			AKI="$AKI"
			ARI="$ARI"
			echo "-- Executing \\\`$TYPE/bundle.sh\\\` on the bundling host"
		SETUP
  )
  
  echo "== Registering $NAME as an AMI"
  AMI=$(ec2-register --show-empty-fields "$BUCKET/$NAME.manifest.xml" \
    | awk '/IMAGE/ { print $2 }')
  if [[ -n $PUBLIC ]]; then
    ec2-modify-image-attribute --show-empty-fields \
      --launch-permission --add all $AMI
  fi
  
  if [[ -n $STARTED_BUNDLING_HOST ]]; then
    echo "-- Terminating the bundling host we launched"
    STARTED_BUNDLING_HOST=''
    host_stop     "$@" || exit 1
    host_teardown "$@" || exit 1
  fi
  
  echo "** ${NAME} registered: ${AMI}"
}

# ===============
# = AMI testing =
# ===============

_test() {
  case $2 in
    "setup")    test_setup    "$@" || exit 1  ;;
    "teardown") test_teardown "$@" || exit 1  ;;
    *)
      test_setup    "$@" || exit 1
      test_run      "$@" || exit 1
      test_teardown "$@" || exit 1
    ;;
  esac
}

test_setup() {
  echo "== Preparing EC2 environment for testing instance"
  TEST_GROUPID=$(ec2-describe-group --show-empty-fields | awk '$1 == "GROUP" \
    && $3 == "'$TEST_GROUP'" { print $3 }')
  if [[ -z $TEST_GROUPID ]]; then
    ec2-add-group --show-empty-fields $TEST_GROUP \
      -d "AMI testing instances" || exit 1
    ec2-authorize --show-empty-fields $TEST_GROUP \
      --protocol tcp --port-range 22 || exit 1
    echo "-- Added security group: $TEST_GROUP"
  fi
  
  TEST_KEYID=$(ec2-describe-keypairs --show-empty-fields \
    | awk '$1 == "KEYPAIR" && $2 == "'$TEST_KEY'" { print $2 }')
  if [[ -z $TEST_KEYID || ! -f "id_rsa-$TEST_KEY" ]]; then
    ec2-delete-keypair --show-empty-fields $TEST_KEY
    rm -f "id_rsa-$TEST_KEY"
    ec2-add-keypair --show-empty-fields $TEST_KEY \
      > "id_rsa-$TEST_KEY" || exit 1
    chmod 400 "id_rsa-$TEST_KEY" || exit 1
    echo "-- Added keypair: $TEST_KEY"
  fi
}

test_teardown() {
  TEST_IIDS=$(ec2-describe-instances --show-empty-fields \
    | awk '$1 == "INSTANCE" && $7 == "'$TEST_GROUP'" && \
      $6 != "terminated" { print $6 }')
  if [[ -z $TEST_IIDS ]]; then
    echo "-- There are no active testing instances, wiping groups and keys"    
    ec2-delete-group --show-empty-fields $TEST_GROUP
    ec2-delete-keypair --show-empty-fields $TEST_KEY && \
      rm -f "id_rsa-$TEST_KEY"
  fi
}

test_run() {
  AMI=$2
  
  AVAILABILITY_ZONES=$(ec2-describe-availability-zones | awk '$1 == "AVAILABILITYZONE" && $3 == "available" { print $2 }')
  for TEST_AVAILABILITY_ZONE in $AVAILABILITY_ZONES; do
    
    echo "== Instantiating ${AMI} in $TEST_AVAILABILITY_ZONE"
    IID=$(ec2-run-instances --group $TEST_GROUP --key $TEST_KEY \
      --availability-zone $TEST_AVAILABILITY_ZONE \
      --instance-type $TEST_ITYPE $AMI | awk '/INSTANCE/ { print $2 }')
    IADDRESS="(nil)"
    while [[ $IADDRESS == "(nil)" ]]; do
      IADDRESS=$(ec2-describe-instances --show-empty-fields $IID \
        | awk '$1 == "INSTANCE" { print $4 }')
    done
    
    echo "== Connecting to testing instance"
    false
    until [[ $? == 0 ]]; do
      sleep 5
			ssh -o "StrictHostKeyChecking no" -i "id_rsa-$TEST_KEY" root@$IADDRESS <<-'ITESTING'
				echo "?? uname: `uname --all`"
				echo "-- Installing packages with pacman"
				pacman --noconfirm -S sudo wget which vi tar nano lzo2 procinfo \
				  libgcrypt less groff file diffutils dialog dbus-core dash cpio binutils \
				  || (shutdown -h now && exit 1)
				
				echo "-- Onlining kernel modules"
				(modprobe loop && modprobe hfs) || (shutdown -h now && exit 1)
				
				shutdown -h now && exit 0
			ITESTING
    done
    
  done
}

# ============================
# = Bundling host management =
# ============================

_host() {
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
  BUNDLING_HOST_GROUPID=$(ec2-describe-group --show-empty-fields | awk '$1 == "GROUP" \
    && $3 == "'$BUNDLING_HOST_GROUP'" { print $3 }')
  if [[ -z $BUNDLING_HOST_GROUPID ]]; then
    ec2-add-group --show-empty-fields $BUNDLING_HOST_GROUP \
      -d "Instances dedicated to bundling AMIs" || exit 1
    ec2-authorize --show-empty-fields $BUNDLING_HOST_GROUP \
      --protocol tcp --port-range 22 || exit 1
    echo "-- Added security group: $BUNDLING_HOST_GROUP"
  fi
  
  BUNDLING_HOST_KEYID=$(ec2-describe-keypairs --show-empty-fields \
    | awk '$1 == "KEYPAIR" && $2 == "'$BUNDLING_HOST_KEY'" { print $2 }')
  if [[ -z $BUNDLING_HOST_KEYID || ! -f "id_rsa-$BUNDLING_HOST_KEY" ]]; then
    ec2-delete-keypair --show-empty-fields $BUNDLING_HOST_KEY
    rm -f "id_rsa-$BUNDLING_HOST_KEY"
    ec2-add-keypair --show-empty-fields $BUNDLING_HOST_KEY \
      > "id_rsa-$BUNDLING_HOST_KEY" || exit 1
    chmod 400 "id_rsa-$BUNDLING_HOST_KEY" || exit 1
    echo "-- Added keypair: $BUNDLING_HOST_KEY"
  fi
  
  KERNEL_HOST_GROUPID=$(ec2-describe-group --show-empty-fields | awk '$1 == "GROUP" \
    && $3 == "'$KERNEL_HOST_GROUP'" { print $3 }')
  if [[ -z $KERNEL_HOST_GROUPID ]]; then
    ec2-add-group --show-empty-fields $KERNEL_HOST_GROUP \
      -d "Instances hosting kernel and kernel modules for bundling AMIs" || exit 1
    ec2-authorize --show-empty-fields $KERNEL_HOST_GROUP \
      --protocol tcp --port-range 22 || exit 1
    echo "-- Added security group: $KERNEL_HOST_GROUP"
  fi
  
  KERNEL_HOST_KEYID=$(ec2-describe-keypairs --show-empty-fields \
    | awk '$1 == "KEYPAIR" && $2 == "'$KERNEL_HOST_KEY'" { print $2 }')
  if [[ -z $KERNEL_HOST_KEYID || ! -f "id_rsa-$KERNEL_HOST_KEY" ]]; then
    ec2-delete-keypair --show-empty-fields $KERNEL_HOST_KEY
    rm -f "id_rsa-$KERNEL_HOST_KEY"
    ec2-add-keypair --show-empty-fields $KERNEL_HOST_KEY \
      > "id_rsa-$KERNEL_HOST_KEY" || exit 1
    chmod 400 "id_rsa-$KERNEL_HOST_KEY" || exit 1
    echo "-- Added keypair: $KERNEL_HOST_KEY"
  fi
}

host_teardown() {
  BUNDLING_HOST_IIDS=$(ec2-describe-instances --show-empty-fields \
    | awk '$1 == "INSTANCE" && $7 == "'$BUNDLING_HOST_GROUP'" && \
      $6 != "terminated" { print $6 }')
  if [[ -z $BUNDLING_HOST_IIDS ]]; then
    echo "-- There are no active bundling hosts, wiping groups and keys"
    ec2-delete-group --show-empty-fields $BUNDLING_HOST_GROUP
    ec2-delete-keypair --show-empty-fields $BUNDLING_HOST_KEY && \
      rm -f "id_rsa-$BUNDLING_HOST_KEY"
    ec2-delete-group --show-empty-fields $KERNEL_HOST_GROUP
    ec2-delete-keypair --show-empty-fields $KERNEL_HOST_KEY && \
      rm -f "id_rsa-$KERNEL_HOST_KEY"
  fi
}

host_start() {
  echo "== Launching bundling host"
  BUNDLING_HOST_IID=$(ec2-run-instances --show-empty-fields $BUNDLING_HOST_AMI \
    --group $BUNDLING_HOST_GROUP --key $BUNDLING_HOST_KEY --instance-type $BUNDLING_HOST_ITYPE \
    --availability-zone $HOST_AVAILABILITY_ZONE \
    | awk '$1 == "INSTANCE" { print $2 }') || exit 1
  
  BUNDLING_HOST_IADDRESS="(nil)"
  while [[ $BUNDLING_HOST_IADDRESS == "(nil)" ]]; do
    BUNDLING_HOST_IADDRESS=$(ec2-describe-instances --show-empty-fields $BUNDLING_HOST_IID \
      | awk '$1 == "INSTANCE" { print $4 }')
  done
  
  echo "== Uploading keys to bundling host"
  false
  until [[ $? == 0 ]]; do
    sleep 5
    scp -o "StrictHostKeyChecking no" -i "id_rsa-$BUNDLING_HOST_KEY" \
      $EC2_PRIVATE_KEY \
      $EC2_CERT \
      root@$BUNDLING_HOST_IADDRESS:/tmp/
  done
  
  case $BUNDLING_HOST_ARCH in
  "i686")   BUNDLING_HOST_EPHEMERAL_STORE='/dev/sda2' ;;
  "x86_64") BUNDLING_HOST_EPHEMERAL_STORE='/dev/sdb'  ;;
  esac
  
  echo "== Connecting to bundling host"
	cat <<-SETUP | ssh -o "StrictHostKeyChecking no" -i "id_rsa-$BUNDLING_HOST_KEY" root@$BUNDLING_HOST_IADDRESS
		echo "== Preparing host for bundling operations"
		cd /tmp
		mount -t ext3 "$BUNDLING_HOST_EPHEMERAL_STORE" /mnt
		
		echo "-- Constructing pacman mirrorlist"
		wget -O mirrorlist "http://repos.archlinux.org/wsvn/packages/pacman-mirrorlist/repos/core-$BUNDLING_HOST_ARCH/mirrorlist?op=dl&rev=0"
		# TODO: Use the API endpoint to leave in the European mirrors if appropriate
		cat mirrorlist | awk '\$1 == "#" { \
		  if(\$0 ~ "United States") {foo = 1} else {foo = 0} }; \
		  {if(foo == 1) print }' | \
		  sed -r 's/^#(Server)/\1/' | sed 's/@carch@/$BUNDLING_HOST_ARCH/' \
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
		pacman --noconfirm -U http://arm.kh.nu/old/extra/os/$BUNDLING_HOST_ARCH/ruby-1.8.7_p174-1-$BUNDLING_HOST_ARCH.pkg.tar.gz
		
		pacman --noconfirm -Sc
		
		echo "-- Installing EC2 AMI tools"
		wget -q http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip
		unzip -oq ec2-ami-tools.zip
		mv ec2-ami-tools-* /mnt/ec2-ami-tools
		
		cat <<'PROFILE' > /root/.profile
			export EC2_AMITOOL_HOME="/mnt/ec2-ami-tools"
		PROFILE
	SETUP
  
  echo "== Launching kernel host"
  KERNEL_HOST_IID=$(ec2-run-instances --show-empty-fields $KERNEL_HOST_AMI \
    --group $KERNEL_HOST_GROUP --key $KERNEL_HOST_KEY --instance-type $KERNEL_HOST_ITYPE \
    --availability-zone $HOST_AVAILABILITY_ZONE \
    | awk '$1 == "INSTANCE" { print $2 }') || exit 1
  
  KERNEL_HOST_IADDRESS="(nil)"
  while [[ $KERNEL_HOST_IADDRESS == "(nil)" ]]; do
    KERNEL_HOST_IADDRESS=$(ec2-describe-instances --show-empty-fields $KERNEL_HOST_IID \
      | awk '$1 == "INSTANCE" { print $4 }')
  done
  
  echo "== Connecting to kernel host"
  false
  until [[ $? == 0 ]]; do
    sleep 5
		ssh -o "StrictHostKeyChecking no" -i "id_rsa-$KERNEL_HOST_KEY" ubuntu@$KERNEL_HOST_IADDRESS <<-SETUP
			sudo apt-get update
			echo "-- Installing kernel"
			sudo apt-get install wireless-crda
		SETUP
  done
  
  case $KERNEL_HOST_ARCH in
  "i686")   KERNEL_HOST_EPHEMERAL_STORE='/dev/sda2' ;;
  "x86_64") KERNEL_HOST_EPHEMERAL_STORE='/dev/sdb'  ;;
  esac
  
	ssh -o "StrictHostKeyChecking no" -i "id_rsa-$KERNEL_HOST_KEY" ubuntu@$KERNEL_HOST_IADDRESS <<-ITESTING
		sudo mount -t ext3 "$KERNEL_HOST_EPHEMERAL_STORE" /mnt
		cd /tmp
		
		sudo wget -q http://ppa.launchpad.net/timg-tpi/ubuntu/pool/main/l/linux-ec2/linux-image-\$(uname -r)_2.6.31-300.2_$KERNEL_ARCH.deb
		sudo dpkg -i linux-image-\$(uname -r)_2.6.31-300.2_$KERNEL_ARCH.deb
		echo "-- Packaging kernel modules"
		sudo tar --create --gzip \
		  --atime-preserve --preserve-permissions --preserve-order --same-owner \
		  --file "/mnt/modules.tar.gz" \
		  --directory "/lib/modules" -- "\$(uname -r)"
	ITESTING
  
  echo "== Uploading kernel host key to bundling host"
  scp -o "StrictHostKeyChecking no" -i "id_rsa-$BUNDLING_HOST_KEY" \
    "id_rsa-$KERNEL_HOST_KEY" \
    root@$BUNDLING_HOST_IADDRESS:/tmp/
  
  echo "== Downloading kernel modules to bundling host"
	ssh -o "StrictHostKeyChecking no" -i "id_rsa-$BUNDLING_HOST_KEY" root@$BUNDLING_HOST_IADDRESS <<-SETUP
		scp -o "StrictHostKeyChecking no" -i "/tmp/id_rsa-$KERNEL_HOST_KEY" \
		  "ubuntu@$KERNEL_HOST_IADDRESS:/mnt/modules.tar.gz" \
		  /mnt/
	SETUP
  
  ec2-terminate-instances --show-empty-fields $KERNEL_HOST_IID
  
  echo "** ${BUNDLING_HOST_IID}[${BUNDLING_HOST_AMI}@${BUNDLING_HOST_ITYPE}] launched: ${BUNDLING_HOST_IADDRESS}"
}

host_stop() {
  echo "== Terminating the $BUNDLING_HOST_ARCH bundling host"
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
    | awk '$1 == "INSTANCE" && $6 == "running" && $7 == "'$BUNDLING_HOST_GROUP'" && \
      $10 == "'$BUNDLING_HOST_ITYPE'" { print $2; exit }' || exit 1
}

# ====================
# = Argument parsing =
# ====================

for arg in $@; do
  if [[ $arg == "--public" ]]; then
    PUBLIC='public';
  fi
done

case $3 in
  "32"|"x86"|"i386"|"i686")
    ARCH="i686"
    EC2_ARCH="i386"
    TEST_ITYPE="m1.small"
    BUNDLING_HOST_AMI="ami-05799e6c"
    BUNDLING_HOST_ARCH=$ARCH
    BUNDLING_HOST_EC2_ARCH=$EC2_ARCH
    BUNDLING_HOST_ITYPE="m1.small"
    KERNEL_ARCH="i386"
    KERNEL_HOST_AMI="ami-fa658593"
    KERNEL_HOST_ARCH=$BUNDLING_HOST_ARCH
    KERNEL_HOST_EC2_ARCH=$BUNDLING_HOST_ARCH
    KERNEL_HOST_ITYPE=$TEST_ITYPE
    AKI="aki-841efeed"
    ARI="ari-9a1efef3"
  ;;
  "64"|"x64"|"x86_64"|"x86-64"|"amd64")
    ARCH="x86_64"
    EC2_ARCH=$ARCH
    TEST_ITYPE="m1.large"
    BUNDLING_HOST_AMI="ami-1b799e72"
    BUNDLING_HOST_ARCH=$ARCH
    BUNDLING_HOST_EC2_ARCH=$EC2_ARCH
    BUNDLING_HOST_ITYPE="m1.large"
    KERNEL_ARCH="amd64"
    KERNEL_HOST_AMI="ami-1a658573"
    KERNEL_HOST_ARCH=$BUNDLING_HOST_ARCH
    KERNEL_HOST_EC2_ARCH=$BUNDLING_HOST_ARCH
    KERNEL_HOST_ITYPE=$TEST_ITYPE
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
  *) _usage "$@" ;;
esac

case $1 in
  "bundle") _bundle "$@"   ;;
  "test")   _test   "$@"   ;;
  "host")   _host   "$@"   ;;
  *)        _usage  "$@"   ;;
esac
