HOST_KEY="bundling-host"
HOST_GROUP="bundling-host"

KEY="bundle-testing"
GROUP="bundle-testing"

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

false
until [[ $? == 0 ]]; do
  sleep 5
  
	cat "-" "./$1/bundle.sh" <<-SETUP | ssh -o "StrictHostKeyChecking no" -i "id_rsa-$HOST_KEY" root@$HOST_IADDRESS
		KEY="$KEY"
		GROUP="$GROUP"
		HOST_ARCH="$HOST_ARCH"
		HOST_EC2_ARCH="$HOST_EC2_ARCH"
		HOST_AMI="$HOST_AMI"
		HOST_ITYPE="$HOST_ITYPE"
		ARCH="$ARCH"
		EC2_ARCH="$EC2_ARCH"
		ITYPE="$ITYPE"
	SETUP
done
