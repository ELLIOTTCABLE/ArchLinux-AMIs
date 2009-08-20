AVAILABILITY_ZONE="us-east-1a"

HOST_KEY="bundling-host"
HOST_GROUP="bundling-host"

KEY="bundle-testing"
GROUP="bundle-testing"

BUCKET="arch-linux"

if [[ $2 == "x86_64" ]]; then
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

HOST_IID=$(./bundling_host.sh get $2) || exit 1

HOST_IADDRESS="(nil)"
while [[ $HOST_IADDRESS == "(nil)" ]]; do
  HOST_IADDRESS=$(ec2-describe-instances --show-empty-fields $HOST_IID \
    | awk '$1 == "INSTANCE" { print $4 }')
done

NAME=$(
	cat "-" "./$1/bundle.sh" <<-SETUP | ssh -o "StrictHostKeyChecking no" -i "id_rsa-$HOST_KEY" root@$HOST_IADDRESS | tail -n1
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
if [[ -z $KEYID ]]; then
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
