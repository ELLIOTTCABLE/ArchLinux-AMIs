#!/bin/bash
# 2009 Copyright Yejun Yang (yejunx AT gmail DOT com)
# Creative Commons Attribution-Noncommercial-Share Alike 3.0 United States License.
# http://creativecommons.org/licenses/by-nc-sa/3.0/us/

## Fillin your real AWS ids and keyfile name
#Cert file
CERT=$(/bin/ls ~/.ec2/cert-*.pem)
#Private Key
PRIKEY=$(/bin/ls ~/.ec2/pk-*.pem)
#User ID
USRID=$(cat ~/.ec2/account_number)
#Upload bucket
BUCKET="elliottcable-amis"
#Access ID
ACCESSID=$(cat ~/.ec2/access_key)
#Secrect
SECRET=$(cat ~/.ec2/secret_key)


PACKS="acl  attr  bash  binutils  bzip2  coreutils  cpio  cracklib  dash  db  dbus-core  dcron  dhcpcd \
    dialog  diffutils  e2fsprogs  file  filesystem  findutils  gawk  gcc-libs  gdbm   gettext  glibc  grep \
    groff  gzip  initscripts  iputils kbd  kernel-headers  \
    less  libarchive  libdownload  libgcrypt  libgpg-error  \
    licenses  logrotate  lzo2  module-init-tools  nano \
    ncurses  net-tools  pacman pacman-mirrorlist  pam  pcre  perl  popt  procinfo  procps  psmisc \
    readline  sed  shadow  syslog-ng  sysvinit  tar  tcp_wrappers  texinfo  tzdata \
    udev  util-linux-ng  vi  wget  which  zlib \
    openssh curl sudo"

if [[ $1 == i686 ]]; then
  ARCH=i686
  EC2_ARCH=i386
else
  ARCH=x86_64
  EC2_ARCH=x86_64
fi
 
ROOT=arch_$ARCH
 
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


cat <<EOF >$ROOT/etc/rc.conf
#
# /etc/rc.conf - Main Configuration for Arch Linux
#

LOCALE="en_US.UTF-8"
HARDWARECLOCK="localtime"
USEDIRECTISA="no"
TIMEZONE="UTC"
KEYMAP="us"
USECOLOR="yes"
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
	/dev/sda1 /     ext3    defaults 1 1
	/dev/sda2 /mnt  ext3    defaults 0 0
	/dev/sda3 swap  swap    defaults 0 0
	none      /proc proc    defaults 0 0
	none      /sys  sysfs   defaults 0 0
	none /dev/pts devpts gid=5,mode=620 0 0
	none /dev/shm tmpfs defaults 0 0 
EOF

cd $ROOT/lib/modules
curl -s http://static.iphash.net/ec2/$EC2_ARCH/2.6.21.7-2.fc8xen.cpio.lzma|lzma -d |cpio -idmv 
cd ../../..

SURF=$(date +%G%m%d)

if [[ "$ARCH" == "i686" ]]; then
    ec2-bundle-vol -c $CERT -k $PRIKEY -u $USRID -r i386 --kernel aki-a71cf9ce --ramdisk ari-a51cf9cc -s 10240 -v arch_i686 --fstab fstab --no-inherit -p arch32-$SURF
    ec2-upload-bundle -b $BUCKET -a $ACCESSID -s $SECRET -m /tmp/arch32-$SURF.manifest.xml
else
    ec2-bundle-vol -c $CERT -k $PRIKEY -u $USRID -r x86_64 --kernel aki-b51cf9dc --ramdisk ari-b31cf9da -s 10240 -v arch_x86_64 --fstab fstab --no-inherit -p arch64-$SURF
    ec2-upload-bundle -b $BUCKET -a $ACCESSID -s $SECRET -m /tmp/arch64-$SURF.manifest.xml
fi
