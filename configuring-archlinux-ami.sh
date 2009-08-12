#!/dev/null
# This 'script' is a set of instructions for preparing and bundling an Arch
# Linux AMI for Amazon's EC2. Bits are to be run on three different
# computers, and there is interaction required, so please follow along and
# run commands individually.

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
ec2-add-keypair bundling-host > ~/.ec2/id_rsa-bundling-host
chmod 600 ~/.ec2/id_rsa-bundling-host

# We also need a security group that will allow us to SSH into our new
# bundling server.
ec2-add-group bundling -d "Instances dedicated to constructing AMIs"
ec2-authorize bundling --protocol tcp --port-range 22
ec2-authorize bundling --protocol icmp --icmp-type-code 8:0

# TODO: Link to my own images here, as well, when they are published
# Now let's select an instance to launch. Mudy, an Arch Linux fan, has
# provided a pair of basic Arch Linux AMIs that we can use as bundling hosts.
# If you like, you can use an Amazon-official Fedora Core image instead. Let's
# see what's available:
ec2-describe-images -o amazon

# I'm most interested in the v1.08 images that are the (as of this writing)
# most up-to-date.
ec2-describe-images -o amazon | grep 'v1.08'

# Since we'll be packaging an x86_64 image in this tutorial, we'll use an
# x86_64 bundling host. While it's possible to bundle an i686 system on an
# x86_64 one, we're not going to bother with that here. Of course, if you want
# to build an i686 system, select the i686 AMI instead.

# You can choose to use the images from that search; the rest of these
# instructions will assume you’re using Mudy’s x86_64 image (`ami-1b799e72`):
# http://blog.mudy.info/2009/04/archlinux-ec2-public-ami/

# Take the AMI above (the string starting with ami-), and pass it to
# ec2-run-instances. You'll also need the group and keypair created above.
# Ensure that you pass the correct instance-type; "m1.small" if you're
# launching an i686 instance, and "m1.large" if you're launching an x86_64:
ec2-run-instances --instance-type m1.large --group bundling \
  --key bundling-host ami-1b799e72
BUNDLING_INSTANCE_ID="i-c50f11ac"

# The output from the above command will include the instance ID of the newly
# created instance, a string starting with i-. Pass that to the
# ec2-describe-instances tool repeatedly until it reports that the new
# instance is operational and "running".
while true; do date; ec2-describe-instances $BUNDLING_INSTANCE_ID; done
BUNDLING_INSTANCE_ADDRESS="ec2-75-101-205-232.compute-1.amazonaws.com"

# Once the instance is operational, we're ready to SSH in!
# The describe command will tell you the public address of the isntance when
# it's available.
ssh root@$BUNDLING_INSTANCE_ADDRESS \
  -i ~/.ec2/id_rsa-bundling-host

### Bundling host setup -----------------------------------------------------
# Now that we're into our new host instance, let's repeat our EC2 tools
# setup, but also install the AMI tools this time around. Most of the
# description is available above, I'm just going to list the commands here.

# First, we’re going to update all the software on our bundling host. We run
# it twice, because the first run usually wants to update `pacman` itself
# before updating other software.
pacman --noconfirm -Syu
pacman --noconfirm -Syu

# Let's download and install the EC2 API tools.
wget http://aur.archlinux.org/packages/ec2-api-tools/ec2-api-tools.tar.gz
tar -xf ec2-api-tools.tar.gz
cd ec2-api-tools
makepkg --noconfirm --asroot --syncdeps --install
cd -

wget http://aur.archlinux.org/packages/ec2-ami-tools/ec2-ami-tools.tar.gz
tar -xf ec2-ami-tools.tar.gz
cd ec2-ami-tools
makepkg --noconfirm --asroot --syncdeps --install
cd -

# Finally, we need a directory to store our certificates
mkdir ~/.ec2
chmod 700 ~/.ec2

# Now you need to leave and re-SSH-in to let the login script added by the
# Java package set some Java–related environment variables for you.

# Now that we've got the tools, we need your certifications and stuff to be
# duplicated on your bundling host. Let's upload all of those. Quit your SSH
# session again and ship everything off to your new server with scp:
exit
scp -i ~/.ec2/id_rsa-bundling-host \
  ~/.ec2/*.pem \
  root@$BUNDLING_INSTANCE_ADDRESS:~/.ec2/
scp -i ~/.ec2/id_rsa-bundling-host \
  ~/.ec2/account_number \
  root@$BUNDLING_INSTANCE_ADDRESS:~/.ec2/
scp -i ~/.ec2/id_rsa-bundling-host \
  ~/.ec2/access_key \
  root@$BUNDLING_INSTANCE_ADDRESS:~/.ec2/
scp -i ~/.ec2/id_rsa-bundling-host \
  ~/.ec2/secret_key \
  root@$BUNDLING_INSTANCE_ADDRESS:~/.ec2/

# And back in again!
ssh root@$BUNDLING_INSTANCE_ADDRESS \
  -i ~/.ec2/id_rsa-bundling-host

# We'll also run our `pacman` mirrorlist through `rankmirrors` now.
# We need Python for `rankmirrors`, so we’ll install that first:
pacman --noconfirm -S python
cat /etc/pacman.d/mirrorlist | sed 's/#Server/Server/' \
  > /etc/pacman.d/mirrorlist.b4.rankmirrors
rankmirrors -v -n0 /etc/pacman.d/mirrorlist.b4.rankmirrors \
  > /etc/pacman.d/mirrorlist

### Image preparation -------------------------------------------------------
# To create an image large enough to hold the OS, we need to mount our
# bundling host’s “ephemeral store” (also known as the “instance store”).
# If you’re on an i686 instance, you’ll need to mount the device at
# `/dev/sda2`, the rest of us will use `/dev/sdb`
mount /dev/sdb /mnt

# Now let's get ourselves an empty image to prepare. First, we'll create an
# empty file.
# Note: You may want to change the size; I'm using 10GBs here, because that's
# the maximum space provided by EC2 for the root filesystem.
# Note: You may want to change the name; I'm using the month that Arch was
# packaged and the architecture it was packaged for.
IMAGE_NAME="ArchLinux-2009.08-x86_64"
dd if=/dev/zero of=/mnt/$IMAGE_NAME.fs bs=1M count=10240

# Now let's stuff a filesystem onto it. I'm using a journaled ext3 filesystem
# with the default options, because it's a known quantity. Feel free to use
# ext4 or tweak the options.
# Note: The -F flag is necessary, becasue we're writing our filesystem to an
# arbitrary file instead of a verifiable block device.
mkfs.ext3 -F /mnt/$IMAGE_NAME.fs

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
mkdir -p /mnt/$IMAGE_NAME
mount -o loop /mnt/$IMAGE_NAME{.fs,}
mkdir -p /mnt/$IMAGE_NAME/{dev,sys,proc}

# These may not be necessary. Not sure.
#mknod -m 600 console c 5 1
#mknod -m 666 null c 1 3
#mknod -m 666 zero c 1 5

mount -o bind {,/mnt/$IMAGE_NAME}/dev
mount -o bind {,/mnt/$IMAGE_NAME}/sys
mount -t proc none /mnt/$IMAGE_NAME/proc

### System installation -----------------------------------------------------
# Now! Time to install us some Arch Linux!
mkdir -p /mnt/$IMAGE_NAME/var/lib/pacman
pacman --noconfirm --root /mnt/$IMAGE_NAME -Sy base base-devel

# We'll need that mirrorlist we already created for this image, we'll just
# copy it in. Accept if it wants to overwrite.
cp {,/mnt/$IMAGE_NAME}/etc/pacman.d/mirrorlist

### System configuration ----------------------------------------------------
# Is it just me, or was that section way to short? I love Arch <3
# Anyway, let's configure some stuff. We'll need to pretend we're actually in
# the new system, so go ahead and chroot in:
chroot /mnt/$IMAGE_NAME /bin/bash

# For whatever reason, while chrooted, we can't acquire network access unless
# we run a new dhcpcd daemon under the chroot environment. Let's do that now.
# Note: We can't kill this new dhcpcd using the -k option without killing our
# bundling host's dhcpcd as well (thus losing access to all of our work
# above). Instead, we'll use lsof to kill it when we're done.
dhcpcd eth0

# This is your chance to install any extra software you want on the image.
# Simply pacman it in, and configure it as desired.

# We're going to install sshd (so we can SSH into our image), as well as
# the OpenNTP daemon, openntpd (so our system's date and time don't get
# confused - this would be especially fatal on EC2, as then our instance
# would no longer be allowed to talk to the EC2 API!)
pacman --noconfirm -S openssh
pacman --noconfirm -S openntpd

# We also want to make sure these run on startup. Edit /etc/rc.conf and add
# them to the DAEMONS array.
nano /etc/rc.conf

# We also need to ensure that SSH connections are allowed. Add the following
# line to /etc/hosts.allow:
#
#     sshd: ALL
#
# This will allow connections to sshd from anybody, anywhere. Don't worry,
# this isn't a particular security hole - EC2 has its own firewalling system.
nano /etc/hosts.allow

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
nano /etc/rc.conf

# Let's do a few more final preperatory things. Edit /etc/locale.gen, and
# uncomment any locales you're interested in.
nano /etc/locale.gen && locale-gen

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
umount /mnt/$IMAGE_NAME/{dev,sys,proc,}

### Image packaging ---------------------------------------------------------
# This is it! Time to package our prepared image and prepare it for uploading
# to Amazon S3 (where images are stored for instantiation)!
mkdir -p /mnt/tmp
ec2-bundle-image --user "$(cat ~/.ec2/account_number)" \
  --cert ~/.ec2/cert-*.pem --privatekey ~/.ec2/pk-*.pem \
  --destination /mnt/tmp --arch i386 \
  --block-device-mapping "ami=/dev/sda1,root=/dev/sda1,ephemeral0=/dev/sdb" \
  --prefix "archlinux-2009.05-i686" \
  --image /mnt/archlinux-2009.05-i686.fs

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
  --key bundling-host ami-7dd23414
ec2-describe-instances i-bde2a3d4
# ... and so on.

