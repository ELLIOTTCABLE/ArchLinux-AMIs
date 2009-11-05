RELEASE="0ab"

### Desired
# curl - needed for the initscripts that download the pubkey
### Required
# bash - shell for initscripts and remote access
# coreutils - basic Linux utilities
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
PACKS="bash coreutils openssh curl filesystem dcron dhcpcd gawk \
  util-linux-ng initscripts iputils licenses logrotate module-init-tools \
  pacman procps psmisc syslog-ng"

TYPE="Nucleus"
NAME="ArchLinux-$ARCH-$TYPE-$RELEASE"
ROOT="/mnt/$NAME.root"

echo "-- Creating filesystem"
mkdir -p "$ROOT"

mkdir "$ROOT/sys/"  ; mount -t sysfs sysfs "$ROOT/sys"
mkdir "$ROOT/proc/" ; mount -t proc   proc "$ROOT/proc"
mkdir "$ROOT/dev/"  ; mount -o bind "/dev" "$ROOT/dev"

mkdir -p "$ROOT/usr/aws/ec2/"

mkdir -p "$ROOT/var/lib/pacman/"
mkdir -p "$ROOT/var/cache/pacman/" ; mount -o bind {,"$ROOT"}"/var/cache/pacman"
echo "-- Syncing pacman repositories"
pacman --noconfirm --noprogressbar --config="/etc/pacman.conf" \
  --root="$ROOT" --cachedir=/var/cache/pacman/pkg \
  -Sy
echo "-- Installing packages"
pacman --noconfirm --noprogressbar --config="/etc/pacman.conf" \
  --root="$ROOT" --cachedir=/var/cache/pacman/pkg \
  -S $PACKS

ldconfig -r "$ROOT"

echo "-- Copying over configuration files"
cp -p {"$ELEMENTS","$ROOT"}"/etc/inittab"
cp -p {"$ELEMENTS","$ROOT"}"/etc/rc.conf"
cp -p {"$ELEMENTS","$ROOT"}"/etc/rc.local"
cp -p {"$ELEMENTS","$ROOT"}"/etc/hosts.deny"
cp -p {"$ELEMENTS","$ROOT"}"/etc/profile.d/ami.sh"

cp -p "/tmp/mirrorlist.ranked" "$ROOT/etc/pacman.d/mirrorlist"

sed -i -r 's/#(en_US\.UTF-8)/\1/' $ROOT/etc/locale.gen
sed -i -r "s/#(UseDNS|PasswordAuthentication) yes/\1 no/" \
  $ROOT/etc/ssh/sshd_config
# TODO: Remove off-continent mirrors, and run rankmirrors
sed -i -r "s/#(Server)/\1/" $ROOT/etc/pacman.d/mirrorlist

echo "-- Installing EC2 kernel modules"
cd $ROOT/lib/modules
curl -s http://static.iphash.net/ec2/$ARCH/2.6.21.7-2.fc8xen.cpio.lzma \
  | lzma -d | cpio -idm
cd -

echo "-- Tearing down environment"
umount "$ROOT/"{"proc","sys","dev","var/cache/pacman"}

echo "-- Bundling image"
$EC2_AMITOOL_HOME/bin/ec2-bundle-vol \
  --cert /tmp/cert-*.pem --privatekey /tmp/pk-*.pem \
  --user "$(cat /tmp/account_number)" \
  --arch $ARCH --kernel $AKI --ramdisk $ARI \
  --size 10240 --fstab "$ELEMENTS/fstab" --volume $ROOT --no-inherit \
  --destination "/mnt" --prefix "$NAME" --batch

echo "-- Uploading image"
$EC2_AMITOOL_HOME/bin/ec2-upload-bundle \
  --access-key "$(cat /tmp/access_key)" \
  --secret-key "$(cat /tmp/secret_key)" \
  --bucket $BUCKET \
  --manifest "/mnt/${NAME}.manifest.xml" --batch --retry

rm -rf /mnt/$NAME*
rm -rf /mnt/img-mnt

echo $NAME
