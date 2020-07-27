#!/bin/bash -e
# Format a "universal" disk layout that can boot any example system here.  (The
# Mac mini example is excluded since APM is incompatible with GPT--that example
# script creates its own bootable image file.)  The fit-PC example compiles the
# i386 bootloader code, which should be installed on the target disk before
# running this script so that it can be converted to a hybrid MBR to support
# booting with the netbook example's firmware.
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
declare -ir esp_mb=447
sfdisk --force "$disk" << EOF
label: gpt
type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, size=${esp_mb}MiB,\
 name="EFI System Partition", attrs=NoBlockIOProtocol
type=FE3A2A5D-4F32-41A7-B725-ACCC3285A309, size=32MiB, name=KERN-A,\
 attrs="50 51 52 54 56"
type=FE3A2A5D-4F32-41A7-B725-ACCC3285A309, size=32MiB, name=KERN-B
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, size= 1GiB, name=ROOT-A
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, size= 1GiB, name=ROOT-B
type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF
declare -r first="$disk$part"1 last="$disk$part"6
test -b "$first" -a -b "$last"

# Write a hybrid MBR into place for non-GPT-aware firmware to find the ESP.
dd bs=1 conv=notrunc count=64 of="$disk" seek=446 if=<(
        # Define the ESP to align with its GPT definition.
        echo -en '\0\x20\x21\0\xEF'$(
                end=$(( esp_mb + 1 << 11 ))
                printf '\\x%02X' \
                    $(( end / 63 % 255 )) $(( end % 63 )) $(( end / 16065 ))
        )'\0\x08\0\0'$(
                for offset in 0 8 16 24
                do printf '\\x%02X' $(( esp_mb << 11 >> offset & 0xFF ))
                done
        )
        # Stupidly reserve all possible space as GPT.
        echo -en '\0\0\x02\0\xEE\xFF\xFF\xFF\x01\0\0\0\xFF\xFF\xFF\xFF'
        # No other MBR partitions are required.
        exec cat /dev/zero
)

# Write the ESP, and put a non-UEFI GRUB configuration file there for later.
mkfs.vfat -F 32 -n EFI-SYSTEM "$first"
declare -rx MTOOLS_SKIP_CHECK=1
mmd -i "$first"  ::/EFI ::/EFI/BOOT ::/script
mcopy -i "$first" - ::/grub.cfg << 'EOF'
set timeout=5

if test /linux_b -nt /linux_a
then set default=boot-b
else set default=boot-a
fi

menuentry 'Boot A' --id boot-a {
        if test -s /kargs_a ; then load_env --file /kargs_a kargs dmsetup ; fi
        linux /linux_a $kargs "$dmsetup" rootwait
        if test -s /initrd_a ; then initrd /initrd_a ; fi
}
menuentry 'Boot B' --id boot-b {
        if test -s /kargs_b ; then load_env --file /kargs_b kargs dmsetup ; fi
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
mkfs.ext4 -F -L data -m 0 "$last"
