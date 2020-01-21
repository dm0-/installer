#!/bin/bash -e
# Format a "universal" disk layout that can boot any example system here.  (The
# Mac mini example is excluded since APM is incompatible with GPT--that example
# script creates its own bootable image file.)  The fit-PC example compiles the
# i386 bootloader code that can be installed on the disk.
#
# This script allocates half of a gigabyte for the boot files, two one-gigabyte
# partitions for root file systems, and the rest is used for persistent scratch
# space.  At least a 4GiB microSD card should be used as the target device.
#
# The dosfstools, e2fsprogs, mtools, and util-linux packages must be installed
# to run this.  Run it as root.

declare -f usage &> /dev/null && exit 1  # This isn't a system install script.
set -euo pipefail
declare -r disk=${1:?Specify the target disk device.} ; test -b "$disk"
[[ $disk == *[0-9] ]] && declare -r part=p || declare -r part=

# Format the given device with GPT partitions.
sfdisk --force "$disk" << EOF
label: gpt
type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, size=447MiB,\
 name="EFI System Partition", attrs=NoBlockIOProtocol
type=FE3A2A5D-4F32-41A7-B725-ACCC3285A309, size= 32MiB,\
 name=KERN-A, attrs="50 51 52 54 56"
type=FE3A2A5D-4F32-41A7-B725-ACCC3285A309, size= 32MiB, name=KERN-B
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, size=  1GiB, name=ROOT-A
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, size=  1GiB, name=ROOT-B
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF
test -b "$disk$part"1 -a -b "$disk$part"6  # Require first and last partitions.

# Write the ESP, and put a non-UEFI GRUB configuration file there for later.
mkfs.vfat -F 32 -n EFI-SYSTEM "$disk$part"1
declare -rx MTOOLS_SKIP_CHECK=1
mmd -i "$disk$part"1  ::/EFI ::/EFI/BOOT
mcopy -i "$disk$part"1 - ::/grub.cfg << 'EOF'
set timeout=5

if test /linux_b -nt /linux_a
then set default=boot-b
else set default=boot-a
fi

menuentry 'Boot A' --id boot-a {
        load_env --file /kargs_a kargs dmsetup
        linux /linux_a $kargs "$dmsetup" rootwait
        if test -s /initrd_a ; then initrd /initrd_a ; fi
}
menuentry 'Boot B' --id boot-b {
        load_env --file /kargs_b kargs dmsetup
        linux /linux_b $kargs "$dmsetup" rootwait
        if test -s /initrd_b ; then initrd /initrd_b ; fi
}

menuentry 'Reboot' --id reboot {
        reboot
}
menuentry 'Power Off' --id poweroff {
        halt
}
EOF

# Make the persistent scratch partition an empty ext4 file system.
mkfs.ext4 -F -L data -m 0 "$disk$part"6
