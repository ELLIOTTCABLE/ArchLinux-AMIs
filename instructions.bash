BUNDLING_VOLUME="vol-5b698332"
BUNDLING_INSTANCE_ID=$(ec2-run-instances --group Void --key Void --monitoring \
  --instance-type m1.xlarge ami-1b799e72 | awk '/INSTANCE/ { print $2 }')
BUNDLING_INSTANCE_ADDRESS="pending"
while [[ $BUNDLING_INSTANCE_ADDRESS == "pending" ]]; do
  BUNDLING_INSTANCE_ADDRESS=$(ec2-describe-instances $BUNDLING_INSTANCE_ID \
    | awk '/INSTANCE/ { print $4 }')
done

ec2-attach-volume $BUNDLING_VOLUME -i $BUNDLING_INSTANCE_ID -d /dev/sdh

sleep 25

scp -o "StrictHostKeyChecking no" -i ~/.ec2/id_rsa-Void \
  ~/.ec2/*.pem \
  ~/.ec2/account_number \
  ~/.ec2/access_key \
  ~/.ec2/secret_key \
  root@$BUNDLING_INSTANCE_ADDRESS:/tmp/

ssh root@$BUNDLING_INSTANCE_ADDRESS \
  -i ~/.ec2/id_rsa-Void


# To create an Arch AMI from scratch, inside another Arch instance
pacman --noconfirm -Syu
pacman --noconfirm -Syu

pacman --noconfirm -S ruby unzip rsync devtools lzma cpio

pacman --noconfirm -Sc

mount -t ext3 /dev/sdh /mnt

wget http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip
unzip ec2-ami-tools.zip
mv ec2-ami-tools-* ec2-ami-tools

export EC2_AMITOOL_HOME="$(pwd)/ec2-ami-tools"

### Desired
# curl - needed for the initscripts that download the pubkey
### Required
# openssh - necessary to SSH in
# filesystem - base filesystem package
# dcron - cron scheduling
# dhcpcd - for network access
# gawk - alternative dependency for initscripts
# util-linux-ng - Piles of UNIX tools I don’t want to get rid of (see:
#   http://freshmeat.net/projects/util-linux/)
# initscripts - necessary for system boot
# iputils - ping
# licenses - fairly sure I’m legally required to include this
# logrotate - intelligent to have everywhere
# module-init-tools - modprobe, etc - needed to utilize modules
# pacman - to install anything we don’t include
# procps - ps, top, kill
# psmisc - killall (initscripts)
# syslog-ng - system logging
PACKS=" \
  gmp \
  openssh \
  curl binutils filesystem dcron dhcpcd \
  gawk \
  util-linux-ng initscripts iputils \
  licenses logrotate \
  module-init-tools pacman \
  procps psmisc syslog-ng"

RELEASE="18"
ARCH="x86_64"
NAME="ArchLinux-$(date +%G%m%d)-$ARCH-$RELEASE"
ROOT="/mnt/$NAME.root"

cat <<EOF > fstab
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

cat <<EOF > pacman.conf
[options]
HoldPkg     = pacman glibc
SyncFirst   = pacman

[core]
Server = http://mirror.cs.vt.edu/pub/ArchLinux/\$repo/os/$ARCH
Server = http://mirror.umoss.org/archlinux/\$repo/os/$ARCH
Server = http://mirror.rit.edu/archlinux/\$repo/os/$ARCH
Server = http://mirrors.gigenet.com/archlinux/\$repo/os/$ARCH
Include = /etc/pacman.d/mirrorlist

[extra]
Server = http://mirror.cs.vt.edu/pub/ArchLinux/\$repo/os/$ARCH
Server = http://mirror.umoss.org/archlinux/\$repo/os/$ARCH
Server = http://mirror.rit.edu/archlinux/\$repo/os/$ARCH
Server = http://mirrors.gigenet.com/archlinux/\$repo/os/$ARCH
Include = /etc/pacman.d/mirrorlist

[community]
Server = http://mirror.cs.vt.edu/pub/ArchLinux/\$repo/os/$ARCH
Server = http://mirror.umoss.org/archlinux/\$repo/os/$ARCH
Server = http://mirror.rit.edu/archlinux/\$repo/os/$ARCH
Server = http://mirrors.gigenet.com/archlinux/\$repo/os/$ARCH
Include = /etc/pacman.d/mirrorlist

EOF

mkarchroot -C pacman.conf $ROOT $PACKS

chmod 666 $ROOT/dev/null
mknod -m 666 $ROOT/dev/random c 1 8
mknod -m 666 $ROOT/dev/urandom c 1 9
mknod -m 600 $ROOT/dev/console c 5 1
mkdir -m 755 $ROOT/dev/pts
mkdir -m 1777 $ROOT/dev/shm


cat <<EOF > $ROOT/etc/rc.conf
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

cat <<EOF > $ROOT/etc/hosts.deny
#
# /etc/hosts.deny
#



# End of file

EOF

cat <<EOF >> $ROOT/etc/rc.local
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

cat <<EOF > $ROOT/etc/inittab
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

sed -i "s/#PasswordAuthentication yes/PasswordAuthentication no/" $ROOT/etc/ssh/sshd_config
sed -i "s/#UseDNS yes/UseDNS no/" $ROOT/etc/ssh/sshd_config

touch $ROOT/root/firstboot

cd $ROOT/lib/modules
curl -s http://static.iphash.net/ec2/$ARCH/2.6.21.7-2.fc8xen.cpio.lzma | lzma -d | cpio -idmv
cd -

./ec2-ami-tools/bin/ec2-bundle-vol \
  --cert /tmp/cert-*.pem --privatekey /tmp/pk-*.pem \
  --user "$(cat /tmp/account_number)" \
  --arch $ARCH --kernel aki-b51cf9dc --ramdisk ari-b31cf9da \
  --size 10240 --fstab fstab --volume $ROOT --no-inherit \
  --destination "/mnt" --prefix "$NAME" --batch --debug

./ec2-ami-tools/bin/ec2-upload-bundle \
  --access-key "$(cat /tmp/access_key)" --secret-key "$(cat /tmp/secret_key)" \
  --bucket "arch-linux" \
  --manifest "/mnt/${NAME}.manifest.xml" --batch --debug --retry

rm -rf /mnt/$NAME*
