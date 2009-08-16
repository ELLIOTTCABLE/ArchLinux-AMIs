# -- -- -- -- ~ -- -- -- -- #
# Creating the instance
ec2-run-instances ami-1b799e72 --group Void --key Void --instance-type m1.large --monitoring --user-data-file ~/Desktop/user-data.json
ec2-attach-volume -d /dev/sdf vol-d5f51fbc -i i-c92f30a0
ec2-attach-volume -d /dev/sdg vol-f9cb2190 -i i-c92f30a0
ec2-associate-address 174.129.205.205 -i i-c92f30a0

# -- -- -- -- ~ -- -- -- -- #
# Preparing it for re–bundling
pacman --noconfirm -Syu
pacman --noconfirm -Syu

pacman --noconfirm -S base-devel
pacman --noconfirm -S unzip rsync

pacman --noconfirm -S man-db
/usr/bin/mandb --quiet

pacman --noconfirm -S ruby rubygems
/usr/bin/gem install json

pacman --noconfirm -Sc

# Prepare fstabs
rm /etc/fstab{,.old} ; nano /etc/fstab # And copy in fstab

# Place for EC2 stuff
mkdir /etc/ec2.d
rm /etc/ec2.d/prepare.rb ; nano /etc/ec2.d/prepare.rb # And copy in prepare.rb
rm /etc/rc.local ; nano /etc/rc.local && chmod +x /etc/rc.local # And copy in rc.local

scp elliottcable@ameny.ell.io:~/.ec2/account_number /mnt/
scp elliottcable@ameny.ell.io:~/.ec2/access_key /mnt/
scp elliottcable@ameny.ell.io:~/.ec2/secret_key /mnt/
scp elliottcable@ameny.ell.io:~/.ec2/*.pem /mnt/

rm -rf /root/.*
touch /etc/ec2.d/firstboot

cd /mnt
wget http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip
unzip ec2-ami-tools.zip
mv ec2-ami-tools-* ec2-ami-tools
export EC2_AMITOOL_HOME="$(pwd)/ec2-ami-tools"
IMAGE_NAME="Arch_Linux-$(date +%G%m%d)-x86_64-1"
./ec2-ami-tools/bin/ec2-bundle-vol \
  --cert /mnt/cert-*.pem --privatekey /mnt/pk-*.pem \
  --user "$(cat /mnt/account_number)" \
  --arch x86_64 --kernel aki-b51cf9dc --ramdisk ari-b31cf9da \
  --size 10240 --fstab /etc/fstab --inherit \
  --prefix "$IMAGE_NAME" \
  --batch --debug && \
./ec2-ami-tools/bin/ec2-upload-bundle \
  --access-key "$(cat /mnt/access_key)" --secret-key "$(cat /mnt/secret_key)" \
  --bucket elliottcable-amis \
  --manifest "/tmp/${IMAGE_NAME}.manifest.xml" \
  --batch --debug --retry

# -- -- -- -- ~ -- -- -- -- #
# Random other crap

yes | mkfs.ext3 -t ext3 /dev/sdf -b 4096 -i 16384 -I 256 -j -J "size=128" -m 1 -M "/home" -O "^huge_file,large_file,dir_index,filetype,resize_inode,sparse_super"
rm -r /home
mkdir /home
mount -l -t ext3 -o "noauto,dev,exec,iversion,mand,relatime,suid,rw,acl,user_xattr,data=writeback" /dev/sdf /home

yes | mkfs.ext3 -t ext3 /dev/sdg -b 4096 -i 16384 -I 256 -j -J "size=128" -m 1 -M "/srv" -O "^huge_file,large_file,dir_index,filetype,resize_inode,sparse_super"
rm -r /srv
mkdir /srv
mount -l -t ext3 -o "noauto,dev,exec,iversion,mand,relatime,suid,rw,acl,user_xattr,data=writeback" /dev/sdg /srv
