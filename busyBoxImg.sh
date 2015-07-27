#!/bin/sh
#
# COPYRIGHT (c)2015 ZIGABYTE CORPORATION. COPYING PERMITTED UNDER GPLv3
#

# Download the latest version of BusyBox
wget http://busybox.net/downloads/busybox-1.15.3.tar.bz2

# Create a busyroot directory
mkdir busyroot

# Extract BusyBox
bunzip2 busybox-1.15.3.tar.bz2
tar xvf busybox-1.15.3.tar

# Configure Busybox
cd busybox-1.15.3
make defconfig

# Make and install BusyBox
make CONFIG_PREFIX=$HOME/busyroot install
chmod 4755 $HOME/busyroot/bin/busybox

# Create required directories
cd $HOME/busyroot
mkdir dev sys etc proc mnt mnt/new-root

# Create the necessary devices(We will use /dev/sdj for the EBS volume, but this could be any block device not used by the normal AMI
MAKEDEV -d $HOME/busyroot/dev -x sdj
MAKEDEV -d $HOME/busyroot/dev -x console
MAKEDEV -d $HOME/busyroot/dev -x null
MAKEDEV -d $HOME/busyroot/dev -x zero

# Create the init file.
mv $HOME/busyroot/sbin/init $HOME/busyroot/sbin/init.orig
cat <<'EOL' > $HOME/busyroot/sbin/init

#!/bin/busybox sh
PATH=/bin:/usr/bin:/sbin:/usr/sbin
NEWDEV="/dev/sdj"
NEWTYP="ext3"
NEWMNT="/mnt/new-root"
OLDMNT="/mnt/old-root"
OPTIONS="noatime,ro"
SLEEP=10

echo "Remounting writable."
mount -o remount,rw /
[ ! -d $NEWMNT ] && echo "Creating directory $NEWMNT." && mkdir -p $NEWMNT

while true ; do
echo "sleeping..."
sleep $SLEEP
echo "Trying to mount $NEWDEV writable."
mount -t $NEWTYP -o rw $NEWDEV $NEWMNT || continue
echo "Mounted."
break;
done

[ ! -d $NEWMNT/$OLDMNT ] && echo "Creating directory $NEWMNT/$OLDMNT." && mkdir -p $NEWMNT/$OLDMNT

echo “Remounting $NEWMNT $OPTIONS."
mount -o remount,$OPTIONS $NEWMNT

echo "Trying to pivot."
cd $NEWMNT
pivot_root . ./$OLDMNT

for dir in /dev /proc /sys; do
echo "Moving mounted file system ${OLDMNT}${dir} to $dir."
mount -move ./${OLDMNT}${dir} ${dir}
done

echo "Trying to chroot"
exec chroot . /bin/sh -c "unmount ./$OLDMNT; exec /sbin/init $*" < /dev/console > /dev/console 2&1
EOL

chmod 755 $HOME/busyroot/sbin/init

# Create the fstab file
cat <<'EOL' > $HOME/busyroot/etc/fstab
/dev/sda1 / ext3 defaults 1 1
none /dev/pts devpts gid=5,mode=620 0 0
none /proc proc defaults 0 0
none /sys sysfs defaults 0 0
EOL

# Create a 4MB loopback file.
cd
dd if=/dev/zero of=busybox.fs bs=1M count=4
mkfs.ext3 busybox.fs

#Mount the loopback file
mkdir $HOME/busyimg
mount -o loop $HOME/busybox.fs $HOME/busyimg
#Copy the staged files and directories to the image. (Technically, the BusyBox image could have been built directly in $HOME/busyimg, but we were not sure how big the image was going to be.)
cp -rp $HOME/busyroot/* $HOME/busyimg

#Un-mount the image
sync
umount -d $HOME/busyimg
