VERSION=4

ec2-run-instances ami-1b799e72 --group Void --key Void --instance-type m1.large --monitoring
BUNDLING_INSTANCE_ID=
ec2-describe-instances $BUNDLING_INSTANCE_ID
BUNDLING_INSTANCE_ADDRESS=

scp -i ~/.ec2/id_rsa-Void \
  ~/.ec2/*.pem \
  root@$BUNDLING_INSTANCE_ADDRESS:/tmp/
scp -i ~/.ec2/id_rsa-Void \
  ~/.ec2/account_number \
  root@$BUNDLING_INSTANCE_ADDRESS:/tmp/
scp -i ~/.ec2/id_rsa-Void \
  ~/.ec2/access_key \
  root@$BUNDLING_INSTANCE_ADDRESS:/tmp/
scp -i ~/.ec2/id_rsa-Void \
  ~/.ec2/secret_key \
  root@$BUNDLING_INSTANCE_ADDRESS:/tmp/

ssh root@$BUNDLING_INSTANCE_ADDRESS \
  -i ~/.ec2/id_rsa-Void


# To create an Arch AMI from scratch, inside another Arch instance
pacman --noconfirm -Syu
pacman --noconfirm -Syu

pacman --noconfirm -S base-devel
pacman --noconfirm -S unzip rsync

pacman --noconfirm -S man-db
/usr/bin/mandb --quiet

pacman --noconfirm -S ruby rubygems
/usr/bin/gem install json

pacman --noconfirm -S devtools lzma cpio

pacman --noconfirm -Sc

PACKS="base base-devel"

ARCH="x86_64"
NAME="ArchLinux-$(date +%G%m%d)-$ARCH-$VERSION"
ROOT="/mnt/$NAME"

cat <<EOF > pacman.conf
[options]
HoldPkg     = pacman glibc
SyncFirst   = pacman

[core]
Server = http://mirror.umoss.org/archlinux/$repo/os/x86_64
Server = http://mirror.cs.vt.edu/pub/ArchLinux/$repo/os/x86_64
Server = http://mirrors.portafixe.com/archlinux/$repo/os/x86_64
Server = http://mirror.rit.edu/archlinux/$repo/os/x86_64
Server = http://archlinux.umflint.edu/$repo/os/x86_64
Server = http://mirrors.gigenet.com/archlinux/$repo/os/x86_64
Server = ftp://mirror.cs.vt.edu/pub/ArchLinux/$repo/os/x86_64
Server = http://mirror.csclub.uwaterloo.ca/archlinux/$repo/os/x86_64
Server = http://distro.ibiblio.org/pub/linux/distributions/archlinux/$repo/os/x86_64
Server = http://mirrors.easynews.com/linux/archlinux/$repo/os/x86_64

[extra]
Server = http://mirror.umoss.org/archlinux/$repo/os/x86_64
Server = http://mirror.cs.vt.edu/pub/ArchLinux/$repo/os/x86_64
Server = http://mirrors.portafixe.com/archlinux/$repo/os/x86_64
Server = http://mirror.rit.edu/archlinux/$repo/os/x86_64
Server = http://archlinux.umflint.edu/$repo/os/x86_64
Server = http://mirrors.gigenet.com/archlinux/$repo/os/x86_64
Server = ftp://mirror.cs.vt.edu/pub/ArchLinux/$repo/os/x86_64
Server = http://mirror.csclub.uwaterloo.ca/archlinux/$repo/os/x86_64
Server = http://distro.ibiblio.org/pub/linux/distributions/archlinux/$repo/os/x86_64
Server = http://mirrors.easynews.com/linux/archlinux/$repo/os/x86_64

[community]
Server = http://mirror.umoss.org/archlinux/$repo/os/x86_64
Server = http://mirror.cs.vt.edu/pub/ArchLinux/$repo/os/x86_64
Server = http://mirrors.portafixe.com/archlinux/$repo/os/x86_64
Server = http://mirror.rit.edu/archlinux/$repo/os/x86_64
Server = http://archlinux.umflint.edu/$repo/os/x86_64
Server = http://mirrors.gigenet.com/archlinux/$repo/os/x86_64
Server = ftp://mirror.cs.vt.edu/pub/ArchLinux/$repo/os/x86_64
Server = http://mirror.csclub.uwaterloo.ca/archlinux/$repo/os/x86_64
Server = http://distro.ibiblio.org/pub/linux/distributions/archlinux/$repo/os/x86_64
Server = http://mirrors.easynews.com/linux/archlinux/$repo/os/x86_64

EOF

mkarchroot -C pacman.conf $ROOT $PACKS

chmod 666 $ROOT/dev/null
mknod -m 666 $ROOT/dev/random c 1 8
mknod -m 666 $ROOT/dev/urandom c 1 9
mknod -m 600 $ROOT/dev/console c 5 1
mkdir -m 755 $ROOT/dev/pts
mkdir -m 1777 $ROOT/dev/shm


cat <<EOF >$ROOT/etc/rc.conf
#
# /etc/rc.conf - Main Configuration for Arch Linux
#

LOCALE="en_US.UTF-8"
HARDWARECLOCK="UTC"
USEDIRECTISA="no"
TIMEZONE="UTC"
KEYMAP="us"
USECOLOR="no"
MOD_AUTOLOAD="yes"
USELVM="no"

HOSTNAME="myhost"

eth0="dhcp"
INTERFACES=(eth0)
ROUTES=()

DAEMONS=(syslog-ng network crond sshd)

EOF

cat <<EOF >$ROOT/etc/hosts.deny
#
# /etc/hosts.deny
#



# End of file

EOF

cat <<EOF>>$ROOT/etc/rc.local
killall nash-hotplug
if [ -f /root/firstboot ]; then
  mkdir /root/.ssh
  curl --retry 3 --retry-delay 5 --silent --fail -o /root/.ssh/authorized_keys http://169.254.169.254/1.0/meta-data/public-keys/0/openssh-key
  if curl --retry 3 --retry-delay 5 --silent --fail -o /root/user-data http://169.254.169.254/1.0/user-data; then
     bash /root/user-data
  fi
  rm -f /root/user-data /root/firstboot   
fi

EOF

cat <<EOF>$ROOT/etc/inittab
#
# /etc/inittab
#
id:3:initdefault:
rc::sysinit:/etc/rc.sysinit
rs:S1:wait:/etc/rc.single
rm:2345:wait:/etc/rc.multi
rh:06:wait:/etc/rc.shutdown
su:S:wait:/sbin/sulogin -p
ca::ctrlaltdel:/sbin/shutdown -t3 -r now
# End of file

EOF

sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/'  $ROOT/etc/ssh/sshd_config
sed -i 's/#UseDNS yes/UseDNS no/' $ROOT/etc/ssh/sshd_config

touch $ROOT/root/firstboot

cat <<-EOF>fstab
/dev/sda1   /             ext3  defaults 1 1
#/dev/sda2  /mnt          ext3  defaults 0 0
/dev/sda3   swap          swap  defaults 0 0
#/dev/sdb   /mnt/store-1  ext3  defaults 0 0
#/dev/sdc   /mnt/store-2  ext3  defaults 0 0
#/dev/sdd   /mnt/store-3  ext3  defaults 0 0
#/dev/sde   /mnt/store-4  ext3  defaults 0 0

### EBS Volumes ###

none /proc proc defaults 0 0
none /sys sysfs defaults 0 0
none /dev/pts devpts gid=5,mode=620 0 0
none /dev/shm tmpfs defaults 0 0

EOF

cd $ROOT/lib/modules
curl -s http://static.iphash.net/ec2/$ARCH/2.6.21.7-2.fc8xen.cpio.lzma|lzma -d |cpio -idmv 
cd ../../..

wget http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip
unzip ec2-ami-tools.zip
mv ec2-ami-tools-* ec2-ami-tools
export EC2_AMITOOL_HOME="$(pwd)/ec2-ami-tools"
./ec2-ami-tools/bin/ec2-bundle-vol \
  --cert /tmp/cert-*.pem --privatekey /tmp/pk-*.pem \
  --user "$(cat /tmp/account_number)" \
  --arch $ARCH --kernel aki-b51cf9dc --ramdisk ari-b31cf9da \
  --size 10240 --fstab fstab --volume $ROOT --no-inherit \
  --prefix "$IMAGE_NAME" \
  --batch --debug && \
./ec2-ami-tools/bin/ec2-upload-bundle \
  --access-key "$(cat /tmp/access_key)" --secret-key "$(cat /tmp/secret_key)" \
  --bucket arch-linux \
  --manifest "/tmp/${IMAGE_NAME}.manifest.xml" \
  --batch --debug --retry
