#!/dev/null
# This 'script' is a set of instructions for preparing and bundling an Arch
# Linux AMI for Amazon's EC2. Bits are to be run on three different
# computers, and there is interaction required, so please follow along and
# run commands individually.

# IMPORTANT NOTE: This is a modified version, to test the same steps using a
# more standard CentOS distribution. All the ArchLinux specific commands are
# commented out, and some CentOS-specific commands have been added.

### Preperation -------------------------------------------------------------
# First, we need the EC2 API tools. They require Java.
# It's worth noting that the OpenJDK package suggested by the Arch Linux
# folks isn't compatible with EC2's command-line API tools, so you've
# probably gotta install Sun's proprietary Java Runtime Environment:
yaourt -S jre

# The jre package will set the $JAVA_HOME environment variable for you, but
# you need to close and re-open your terminal.
exit

# Now let's download and install the EC2 stuff to ~/.ec2:
yaourt -S wget unzip
wget http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip
unzip ec2-api-tools.zip
mv ec2-api-tools-* .ec2

# At this point, you need to visit the EC2 site, and get a few pieces of
# data.
# First, you'll download your X.509 certficiates into ~/.ec2/ (they
# should be two seperate .pem files).
# Second, you'll copy-paste your "Account Number", "Access Key ID", and
# "Secret Access Key" into ~/.ec2/ as files named account_number,
# access_key, and secret_key respectively.
links http://aws-portal.amazon.com/gp/aws/developer/account/index.html?actio\
n=access-key

# This bit, you'll have to run any time you open a new terminal; it sets
# environment variables relevant to the EC2 tools:
export PATH="$PATH:$HOME/.ec2/bin"
export EC2_HOME="$HOME/.ec2"
export EC2_CERT="$(/bin/ls $EC2_HOME/cert-*.pem)"
export EC2_PRIVATE_KEY="$(/bin/ls $EC2_HOME/pk-*.pem)"

### Bundling host launching -------------------------------------------------
# Now you've got all the data you'll need. Let's prepare ourselves to launch
# a bundling instance!

# We need a private key now, for the instance we're about to create:
ec2-add-keypair ami-bundler > ~/.ec2/id_rsa-ami-bundler
chmod 600 ~/.ec2/id_rsa-ami-bundler

# We also need a security group that will allow us to SSH into our new
# bundling server.
ec2-add-group bundling -d "Systems dedicated to bundling other AMIs."
ec2-authorize bundling --protocol tcp --port-range 22
ec2-authorize bundling --protocol icmp --icmp-type-code -1:-1

# Now let's select an instance to launch. There are no decent Arch Linux
# images available as of this writing, so we'll be using an Amazon-official
# Fedora Core image instead. Let's see what's available:
ec2-describe-images -o amazon

# I'm most interested in the v1.08 images that are the (as of this writing)
# most up-to-date.
ec2-describe-images -o amazon | grep 'v1.08'

# Since we'll be packaging an i686 image in this tutorial, we'll use an i686
# bundling host in this tutorial. While it's possible to bundle an i686
# system on an x86_64 one, we're not going to bother with that here.
# Of course, if you want to build an x86_64 system, select the x86_64 AMI
# instead.

# Take the AMI above (the string starting with ami-), and pass it to
# ec2-run-instances. You'll also need the group and keypair created above.
# Ensure that you pass the correct instance-type; "m1.small" if you're
# launching an i686 instance, and "m1.large" if you're launching an x86_64:
#ec2-run-instances --instance-type m1.small --group bundling \
#  --key ami-bundler ami-5647a33f
ec2-run-instances --instance-type m1.small --group bundling \
  --key ami-bundler ami-0459bc6d

# The output from the above command will include the instance ID of the newly
# created instance, a string starting with i-. Pass that to the
# ec2-describe-instances tool repeatedly until it reports that the new
# instance is operational and "running".
while true; do date; ec2-describe-instances i-ad286fc4; done

# Once the instance is operational, we're ready to SSH in!
# The describe command will tell you the public address of the isntance when
# it's available.
ssh root@ec2-67-202-10-136.compute-1.amazonaws.com \
  -i ~/.ec2/id_rsa-ami-bundler

### Bundling host setup -----------------------------------------------------
# Now that we're into our new host instance, let's repeat our EC2 tools
# setup, but also install the AMI tools this time around. Most of the
# description is available above, I'm just going to list the commands here.
yum update # We want everything up-to-date!

# First, we'll need Java for the EC2 tools. Unfortunately, Fedora seems to be
# missing any sort of sensible package manager package for Java, so we have
# to deal with it the messy way.
# This URL may not work for you. Copy the download URL for the Linux RPM
# package from this page: http://www.java.com/en/download/manual.jsp
# (Obviously, if you're running on an x86_64 bundling host, download the
# x86_64 Java RPM)
mkdir -p /usr/java
cd /usr/java
wget http://javadl.sun.com/webapps/download/AutoDL?BundleId=29209 \
  -O jre-6u13-linux-i586-rpm.bin
chmod o+x !$
./!$

touch /etc/profile.d/java.sh
chmod +x !$
echo 'export JAVA_HOME="/usr/java/latest"' >> !$
echo 'export JAVA_PATH="$JAVA_HOME"' >> !$
echo 'export PATH="$PATH:$JAVA_HOME/bin"' >> !$
# Blah, I bet you can't wait 'till we get an arch box running now, right? d-:

# Now you need to leave and re-SSH-in to get those variables set.
exit
ssh root@ec2-67-202-10-136.compute-1.amazonaws.com \
  -i ~/.ec2/id_rsa-ami-bundler

# Check that they're properly set. This should list a bunch of java
# directories.
ls $JAVA_HOME/bin

# Let's finally download and install the EC2 API tools.
cd ~/
wget http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip
unzip ec2-api-tools.zip
mv ec2-api-tools-* .ec2
wget http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip
unzip ec2-ami-tools.zip
mv ec2-ami-tools-*/etc .ec2/etc
mv ec2-ami-tools-*/bin/* .ec2/bin/
mv ec2-ami-tools-*/lib/* .ec2/lib/

# Now that we've got the tools, we need your certifications and stuff to be
# duplicated on your bundling host. Let's upload all of those. Quit your SSH
# session again and ship everything off to your new server with scp:
exit
scp -i ~/.ec2/id_rsa-ami-bundler \
  ~/.ec2/*.pem \
  root@ec2-67-202-10-136.compute-1.amazonaws.com:~/.ec2/
scp -i ~/.ec2/id_rsa-ami-bundler \
  ~/.ec2/account_number \
  root@ec2-67-202-10-136.compute-1.amazonaws.com:~/.ec2/
scp -i ~/.ec2/id_rsa-ami-bundler \
  ~/.ec2/access_key \
  root@ec2-67-202-10-136.compute-1.amazonaws.com:~/.ec2/
scp -i ~/.ec2/id_rsa-ami-bundler \
  ~/.ec2/secret_key \
  root@ec2-67-202-10-136.compute-1.amazonaws.com:~/.ec2/

# And back in again!
ssh root@ec2-67-202-10-136.compute-1.amazonaws.com \
  -i ~/.ec2/id_rsa-ami-bundler

# We also need our new EC2 tools in the $PATH.
touch /etc/profile.d/ec2.sh
chmod +x !$
echo 'export PATH="$HOME/.ec2/bin:$PATH"' >> !$
echo 'export EC2_HOME="$HOME/.ec2"' >> !$
echo 'export EC2_CERT="$(/bin/ls $EC2_HOME/cert-*.pem)"' >> !$
echo 'export EC2_PRIVATE_KEY="$(/bin/ls $EC2_HOME/pk-*.pem)"' >> !$

# Again, you gotta close the SSH session and re-open it.
exit
ssh root@ec2-67-202-10-136.compute-1.amazonaws.com \
  -i ~/.ec2/id_rsa-ami-bundler

# Now we need to get pacman, to install Arch Linux's base packages with.
# Unfortunately, it'd be difficult to install all of its dependencies on
# this Fedora box, so we'll use a statically-built pacman instead.
# Of course, this version number may have changed since this writing;
# make sure to check the server for the exact URL of this file:
# http://repo.archlinux.fr/i686/
# Note: Also, if you're building on an x86_64 system, that's the way to go.
#wget http://repo.archlinux.fr/i686/pacman-static-3.2.2-1.pkg.tar.gz
#tar -xzvf ~/pacman-static-3.2.2-1.pkg.tar.gz -C /

# We also need a mirrorlist and configuration file for pacman. We'll get
# those from the actual pacman packages. We'll also run the mirrorlist
# through rankmirrors now.
# Note: The archlinux repository, while guaranteed (hence why I'm using it
# here), is very, very slow. If you know of another mirror, use it.
#mkdir pacman
#wget http://ftp.archlinux.org/core/os/i686/pacman-3.2.2-1-i686.pkg.tar.gz -O pacman.pkg.tar.gz
#tar -xzvf pacman.pkg.tar.gz -C pacman
#wget http://ftp.archlinux.org/core/os/i686/pacman-mirrorlist-20090509-1-i686.pkg.tar.gz -O mirrorlist.pkg.tar.gz
#tar -xzvf mirrorlist.pkg.tar.gz -C pacman
#mv {pacman,}/etc/pacman.conf
#mv {pacman,}/usr/bin/rankmirrors

#mkdir -p /etc/pacman.d/
#cat pacman/etc/pacman.d/mirrorlist | sed 's/#Server/Server/' \
#  > /etc/pacman.d/mirrorlist.b4.rankmirrors
#rankmirrors -v -n0 /etc/pacman.d/mirrorlist.b4.rankmirrors \
#  > /etc/pacman.d/mirrorlist

### Image preparation -------------------------------------------------------
# Now let's get ourselves an empty image to prepare. First, we'll create an
# empty file.
# Note: You may want to change the size; I'm using 10GBs here, because that's
# the maximum space provided by EC2 for the root filesystem.
# Note: You may want to change the name; I'm using the month that Arch was
# packaged and the architecture it was packaged for.
# DEBUG: Going to use 1GB for now. Just in case the image is coming out slightly too large.
#dd if=/dev/zero of=/mnt/archlinux-2009.05-i686.fs bs=1M count=10000
dd if=/dev/zero of=/mnt/centos-2009.06-i686.fs bs=1M count=1000

# Now let's stuff a filesystem onto it. I'm using a journaled ext3 filesystem
# with the default options, because it's a known quantity. Feel free to use
# ext4 or tweak the options.
# Note: The -F flag is necessary, becasue we're writing our filesystem to an
# arbitrary file instead of a verifiable block device.
#mkfs.ext3 -F /mnt/archlinux-2009.05-i686.fs
mkfs.ext3 -F /mnt/centos-2009.06-i686.fs

# Now, to mount the loopback filesystem, we need the loop module. The AMI I
# chose to launch above had some useful kernel modules (such as loop) bundled
# with it, so we simply have to run the following.
# Note: If your bundling host doesn't have some modules bundled with it, they
# can be acquired from the official Amazon EC2 buckets. Google can tell you
# more, as can the EC2 forums.
# Another note: This is already loaded in the AMI I chose. Thus, this command is commented out.
#modprobe loop

# Now let's mount everything! We're going to mount up our new image, as well
# as some linux devices we'll need.
#mkdir -p /mnt/archlinux-2009.05-i686
#mount -o loop /mnt/archlinux-2009.05-i686{.fs,}
#mkdir -p /mnt/archlinux-2009.05-i686/{dev,sys,proc}
mkdir -p /mnt/centos-2009.06-i686
mount -o loop /mnt/centos-2009.06-i686{.fs,}
mkdir -p /mnt/centos-2009.06-i686/{dev,sys,proc}

# These may not be necessary. Not sure.
#mknod -m 600 console c 5 1
#mknod -m 666 null c 1 3
#mknod -m 666 zero c 1 5

#mount -o bind {,/mnt/archlinux-2009.05-i686}/dev
#mount -o bind {,/mnt/archlinux-2009.05-i686}/sys
#mount -t proc none /mnt/archlinux-2009.05-i686/proc
mount -o bind {,/mnt/centos-2009.06-i686}/dev
mount -o bind {,/mnt/centos-2009.06-i686}/sys
mount -t proc none /mnt/centos-2009.06-i686/proc

### System installation -----------------------------------------------------
# Now! Time to install us some Arch Linux!
#mkdir -p /mnt/archlinux-2009.05-i686/var/lib/pacman
#pacman.static -r /mnt/archlinux-2009.05-i686 -Sy
#pacman.static -r /mnt/archlinux-2009.05-i686 -S base base-devel

# We'll need that mirrorlist we already created for this image, we'll just
# copy it in. Accept if it wants to overwrite.
#cp {,/mnt/archlinux-2009.05-i686}/etc/pacman.d/mirrorlist

touch yum-xen.conf
echo '[main]' >> yum-xen.conf
echo 'cachedir=/var/cache/yum' >> yum-xen.conf
echo 'debuglevel=2' >> yum-xen.conf
echo 'logfile=/var/log/yum.log' >> yum-xen.conf
echo 'exclude=*-debuginfo' >> yum-xen.conf
echo 'gpgcheck=0' >> yum-xen.conf
echo 'obsoletes=1' >> yum-xen.conf
echo 'reposdir=/dev/null' >> yum-xen.conf
echo '' >> yum-xen.conf
echo '[base]' >> yum-xen.conf
echo 'name=Fedora Core 4 - $basearch - Base' >> yum-xen.conf
echo 'baseurl=http://archive.fedoraproject.org/pub/archive/fedora/linux/core/4/i386/os/' >> yum-xen.conf
echo 'enabled=1' >> yum-xen.conf

yum -c yum-xen.conf --installroot=/mnt/centos-2009.06-i686 -y groupinstall Base

mkdir -p /mnt/centos-2009.06-i686/etc/sysconfig/network-scripts
touch /mnt/centos-2009.06-i686/etc/sysconfig/network-scripts/ifcfg-eth0
echo 'DEVICE=eth0' >> !$
echo 'BOOTPROTO=dhcp' >> !$
echo 'ONBOOT=yes' >> !$
echo 'TYPE=Ethernet' >> !$
echo 'USERCTL=yes' >> !$
echo 'PEERDNS=yes' >> !$
echo 'IPV6INIT=no' >> !$

mkdir -p /mnt/ec2-fs/etc/sysconfig/
touch /mnt/ec2-fs/etc/sysconfig/network
echo 'NETWORKING=yes' >> !$


### System configuration ----------------------------------------------------
# Is it just me, or was that section way to short? I love Arch <3
# Anyway, let's configure some stuff. We'll need to pretend we're actually in
# the new system, so go ahead and chroot in:
#chroot /mnt/archlinux-2009.05-i686 /bin/bash
chroot /mnt/centos-2009.06-i686 /bin/bash

# For whatever reason, while chrooted, we can't acquire network access unless
# we run a new dhcpcd daemon under the chroot environment. Let's do that now.
# Note: We can't kill this new dhcpcd using the -k option without killing our
# bundling host's dhcpcd as well (thus losing access to all of our work
# above). Instead, we'll use lsof to kill it when we're done.
#dhcpcd eth0
dhclient eth0

# This is your chance to install any extra software you want on the image.
# Simply pacman it in, and configure it as desired.

# We're going to install sshd (so we can SSH into our image), as well as
# the OpenNTP daemon, openntpd (so our system's date and time don't get
# confused - this would be especially fatal on EC2, as then our instance
# would no longer be allowed to talk to the EC2 API!)
#pacman -S openssh
#pacman -S openntpd

# We also want to make sure these run on startup. Edit /etc/rc.conf and add
# them to the DAEMONS array.
#nano /etc/rc.conf

# We also need to ensure that SSH connections are allowed. Add the following
# line to /etc/hosts.allow:
#
#     sshd: ALL
#
# This will allow connections to sshd from anybody, anywhere. Don't worry,
# this isn't a particular security hole - EC2 has its own firewalling system.
#nano /etc/hosts.allow

# Now that you've made any changes you wish to your image, we're going to do
# some final preperation to make it play friendly with EC2. Specifically, we
# want to download the proper root public-key from the EC2 API when the
# image is instantiated (i.e., the first time it boots).
# Unfortunately, I don't know how to do this yet. TODO: Figure this out.
# Instead, we'll just hardcode a root password into our image. Protip: This
# isn't very secure. )-:
passwd

# Finally, we need to make sure the instance's network is configured on boot.
# This is managed with DHCP, so we just need to modify our rc.conf - edit
# /etc/rc.conf, and replace the eth0= line with the following:
#
#     eth0="dhcp"
#
# This will force the instance to instantiate dhcpcd on boot, and connect it
# to eth0, EC2's virtual network port.
#nano /etc/rc.conf

# Let's do a few more final preperatory things. Edit /etc/locale.gen, and
# uncomment any locales you're interested in.
#nano /etc/locale.gen && locale-gen

# Finally, we'll prepare the fstab for EC2's virtual drive configuration.
# More information on how you should configure your drives for EC2 is
# available here:
# http://docs.amazonwebservices.com/AWSEC2/latest/DeveloperGuide/index.html?
#   concepts-amis-and-instances.html
# Since there's two very different setups, I'll document both i686 and x86_64
# setup here. The second, commented set of settings should be uncommented and
# traded for the first set if you're building an x86_64 image.
mv /etc/fstab{,.old}

echo 'none /dev/pts devpts defaults 0 0' >> /etc/fstab
echo 'none /dev/shm tmpfs defaults 0 0' >> /etc/fstab
echo '# i686 (m1.small, c1.medium)' >> /etc/fstab
echo '/dev/sda1 / ext3 defaults 0 1' >> /etc/fstab
echo '/dev/sda2 /mnt ext3 defaults 0 2' >> /etc/fstab
echo '/dev/sda3 swap swap defaults 0 0' >> /etc/fstab
echo '# x86_64 (m1.large, m1.xlarge, c1.xlarge)' >> /etc/fstab
echo '#/dev/sda1 / ext3 defaults 0 1' >> /etc/fstab
echo '#/dev/sdb /mnt ext3 defaults 0 2' >> /etc/fstab

# Now that we're all done, let's exit our chroot environment and get ready to
# bundle this image up.
exit

# Unfortunately, that dhcpcd instance we booted up earlier is clingy, and
# doesn't want to let go of our chrooted /dev/null. To unmount our chrooted
# /dev (and subsequently our entire chroot), we have to get rid of that
# process. This implies some disturbing connotations, however: Killing that
# dhcpcd will cause it to bring the eth0 interface down; that will cause our
# instance to lose network access to EC2. Incidentally, that also loses us
# access to our carefully configured bundling host, and all of our work so
# far.
# That's bad. We're going to avoid that by simultaneously killing all network
# processes (both the host's dhclient and our chroot's dhcpcd) and then
# launching a new dhclient on our host.
# Use ps as below to get the PIDs of both the dhclient and dhcpcd instance.
# Then kill them both, and use a bash ; to immediately launch a new dhclient.
ps aux | grep -E '(dhc|eth0)'
kill -9 785 12120 ; dhclient

# Now we can unmount!
#umount /mnt/archlinux-2009.05-i686/{dev,sys,proc,}
umount /mnt/centos-2009.06-i686/{dev,sys,proc,}

### Image packaging ---------------------------------------------------------
# This is it! Time to package our prepared image and prepare it for uploading
# to Amazon S3 (where images are stored for instantiation)!
mkdir -p /mnt/tmp
ec2-bundle-image --user "$(cat ~/.ec2/account_number)" \
  --cert ~/.ec2/cert-*.pem --privatekey ~/.ec2/pk-*.pem \
  --destination /mnt/tmp --arch i386 \
  --block-device-mapping "ami=/dev/sda1,root=/dev/sda1,ephemeral0=/dev/sdb" \
  --prefix "centos-2009.06-i686" \
  --image /mnt/centos-2009.06-i686.fs

### Image uploading ---------------------------------------------------------
# We need an S3 bucket to upload to, so let's install the s3cmd package:
yum install s3cmd

# Let's configure s3cmd. Too bad it doesn't take configuration as command-
# line flags, right? Silly UI fail (-:
echo '[default]' >> ~/.s3cfg
echo "access_key = $(cat ~/.ec2/access_key)" >> ~/.s3cfg
echo "secret_key = $(cat ~/.ec2/secret_key)" >> ~/.s3cfg

# Now, let's make a bucket to put our AMIs in. This has to be globally
# unique. I suggest using your name or company or something.
s3cmd mb s3://elliottcable-amis

# And now for the uploading!
ec2-upload-bundle \
  --access-key "$(cat ~/.ec2/access_key)" \
  --secret-key "$(cat ~/.ec2/secret_key)" \
  --bucket elliottcable-amis --acl public-read --location US \
  --manifest /mnt/tmp/archlinux-2009.05-i686.manifest.xml

# The very last step is registering your image as an instantiable AMI! Let's
# do that. The ami- string returned by this command is your new AMI!
ec2-register --verbose --headers --show-empty-fields \
  elliottcable-amis/archlinux-2009.05-i686.manifest.xml

# You're all done. Now you can exit the SSH to the bundling host...
exit
# ... and if you aren't going to bundle any more instances on that host, kill
# it...
ec2-terminate-instances i-ad286fc4
# ... and try out your new image!
# Note: You'll probably want to create new security groups and keys for this,
# but the ones we've been using for the bundling host will work for now.
ec2-run-instances --instance-type m1.small --group bundling \
  --key ami-bundler ami-7dd23414
ec2-describe-instances i-bde2a3d4
# ... and so on.
