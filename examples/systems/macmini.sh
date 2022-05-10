# SPDX-License-Identifier: GPL-3.0-or-later
# This is an example Gentoo build for a specific target system, the first
# generation Apple Mac mini (based on the PowerPC G4 CPU).  It demonstrates
# cross-compiling for a 32-bit PPC device and generating an Open Firmware ELF
# bootloader program.
#
# The GPT image is completely replaced with APM so that this system's version
# of Open Firmware is able to read it.  It formats a 4GiB disk image by default
# partitioned for two root file systems and a persistent /var partition.
#
# After writing apm.img to a USB device, it can be booted at the Open Firmware
# prompt (by holding Command-Option-O-F at startup or by setting the NVRAM
# variable auto-boot?=false) with the command "boot usb0/disk:2,::tbxi".

options+=(
        [distro]=gentoo         # Use Gentoo to build this image from source.
        [arch]=powerpc          # Target PowerPC G4 CPUs.
        [bootable]=1            # Build a kernel for this system.
        [networkd]=1            # Let systemd manage the network configuration.
        [squash]=1              # Use a compressed file system to save space.
        [verity_sig]=1          # Require verifying all verity root hashes.
)

packages+=(
        # Utilities
        app-arch/cpio
        app-arch/tar
        app-arch/unzip
        app-editors/emacs
        dev-util/strace
        dev-vcs/git
        sys-apps/diffutils
        sys-apps/file
        sys-apps/findutils
        sys-apps/gawk
        sys-apps/grep
        sys-apps/kbd
        sys-apps/less
        sys-apps/man-pages
        sys-apps/sed
        sys-apps/which
        sys-devel/patch
        sys-process/lsof
        sys-process/procps
        ## Accounts
        app-admin/sudo
        sys-apps/shadow
        ## Hardware
        sys-apps/ibm-powerpc-utils
        sys-apps/pciutils
        sys-apps/usbutils
        ## Network
        net-firewall/iptables
        net-misc/openssh
        net-misc/wget
        net-wireless/wpa_supplicant
        sys-apps/iproute2

        # Disks
        net-fs/sshfs
        sys-fs/cryptsetup
        sys-fs/e2fsprogs
        sys-fs/hfsutils
        sys-fs/mac-fdisk

        # Graphics
        lxde-base/lxdm
        media-sound/pavucontrol
        media-video/pipewire
        x11-apps/xev
        x11-base/xorg-server
        xfce-base/xfce4-meta
)

packages_buildroot+=(
        # The target hardware requires firmware.
        sys-kernel/linux-firmware

        # Support making a bootable New World APM image.
        sys-fs/hfsutils
        sys-fs/mac-fdisk
)

function initialize_buildroot() {
        local -r portage="$buildroot/usr/${options[host]}/etc/portage"

        # Tune compilation for the PowerPC G4.
        $sed -i \
            -e '/^COMMON_FLAGS=/s/[" ]*$/ -mcpu=7450 -maltivec -mabi=altivec -ftree-vectorize&/' \
            "$portage/make.conf"
        $cat << 'EOF' >> "$portage/make.conf"
CPU_FLAGS_PPC="altivec"
RUSTFLAGS="-C target-cpu=7450"
USE="$USE ppcsha1"
EOF

        # Use the RV280 driver for the ATI Radeon 9200 graphics processor.
        echo 'VIDEO_CARDS="radeon r200"' >> "$portage/make.conf"

        # Enable general system settings.
        echo >> "$portage/make.conf" 'USE="$USE' \
            berkdb dbus elfutils emacs gdbm git glib json libnotify libxml2 magic ncurses pcre2 readline sqlite udev uuid xml \
            bidi fontconfig fribidi harfbuzz icu idn libidn2 nls truetype unicode \
            apng exif gif imagemagick jbig jpeg jpeg2k png svg tiff webp xpm \
            a52 alsa cdda faad flac libcanberra libsamplerate mp3 ogg opus pulseaudio sndfile sound speex vorbis \
            aacs aom bdplus bluray cdio dav1d dvd ffmpeg libaom mpeg theora vpx x265 \
            brotli bzip2 gzip lz4 lzma lzo snappy xz zlib zstd \
            cryptsetup gcrypt gmp gnutls gpg mpfr nettle \
            curl http2 ipv6 libproxy mbim modemmanager networkmanager wifi wps \
            acl caps cracklib fprint hardened pam policykit seccomp smartcard xattr xcsecurity \
            acpi dri gallium gusb kms libglvnd libkms opengl upower usb uvm vaapi vdpau \
            cairo colord gtk gtk3 gui lcms libdrm pango uxa wnck X xa xcb xft xinerama xkb xorg xrandr xvmc xwidgets \
            aio branding haptic jit lto offensive pcap realtime system-info threads udisks utempter vte \
            dynamic-loading gzip-el hwaccel postproc startup-notification toolkit-scroll-bars wide-int \
            -cups -dbusmenu -debug -geolocation -gstreamer -llvm -oss -perl -python -sendmail \
            -ffmpeg -networkmanager'"'

        # Install QEMU to run virtual machines.
        packages+=(app-emulation/qemu)
        $cat << 'EOF' >> "$portage/package.accept_keywords/qemu.conf"
app-emulation/qemu *
net-libs/libslirp *
EOF
        $mkdir -p "$portage/patches/app-emulation/qemu"
        $cat << 'EOF' >> "$portage/patches/app-emulation/qemu/ppc.patch"
--- a/common-user/meson.build
+++ b/common-user/meson.build
@@ -1,4 +1,6 @@
+if host_arch != 'ppc'
 common_user_inc += include_directories('host/' / host_arch)
+endif
 
 user_ss.add(files(
   'safe-syscall.S',
EOF

        # Build GRUB to boot from Open Firmware.
        echo 'GRUB_PLATFORMS="ieee1275"' >> "$buildroot/etc/portage/make.conf"
        packages_buildroot+=(sys-boot/grub)
}

function customize_buildroot() {
        # Build less useless stuff on the host from bad dependencies.
        echo >> /etc/portage/make.conf 'USE="$USE' \
            -cups -debug -emacs -geolocation -gstreamer -llvm -oss -perl -python -sendmail -X'"'

        # Configure the kernel by only enabling this system's settings.
        write_system_kernel_config
}

function customize() {
        drop_development
        store_home_on_var +root

        echo macmini > root/etc/hostname

        # Drop extra unused paths.
        exclude_paths+=(
                usr/lib/firmware
                usr/local
                usr/share/qemu/'*'{aarch,arm,efi,hppa,riscv,s390,sparc,x86_64}'*'
        )

        # Define how to mount the bootstrap partition, but leave it unmounted.
        mkdir root/boot ; echo >> root/etc/fstab PARTLABEL=bootstrap \
            /boot hfs defaults,noatime,noauto,nodev,noexec,nosuid

        # Use a persistent /var partition with bare ext4.
        echo "UUID=${options[var_uuid]:=$(</proc/sys/kernel/random/uuid)}" \
            /var ext4 defaults,nodev,nosuid,x-systemd.growfs,x-systemd.rw-only 1 2 >> root/etc/fstab

        # Write a script with an example boot command to test with QEMU.
        cat << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu
exec qemu-system-ppc -nodefaults \
    -machine mac99,via=pmu -cpu g4 -m 1G -vga std -nic user,model=sungem \
    -device pci-ohci -device usb-kbd -device usb-mouse \
    -prom-env 'boot-device=hd:2,grub.elf' \
    -drive file="${IMAGE:-apm.img}",format=raw,media=disk,snapshot=on \
    "$@"
EOF
}

# Override image partitioning to use APM, since it's incompatible with GPT.
function partition() if opt bootable
then
        local -ir bs=512 image_size="${options[image_size]:=3959422976}"
        local -ir boot_size=$(( 64 << 20 )) slot_size=$(( 1 << 30 )) slots=2
        local -i i base=1 length=63  # Start after the implicit map blocks.

        # Build a PowerPC GRUB image that Open Firmware can use.
        grub-mkimage \
            --compression=none \
            --format=powerpc-ieee1275 \
            --output=grub.elf \
            --prefix= \
            halt hfs ieee1275_fb linux loadenv minicmd normal part_apple reboot test

        # Write some basic GRUB configuration for boot slot switching.
        sed < kernel_args.txt > kargs.env \
            -e '1s/^/# GRUB Environment Block\nkargs=/' \
            -e 's/ *\(dm-mod.create=\|DVR=\)"\([^"]*\)"\(.*\)/\3\ndmsetup=\1\2/' \
            -e 's,/dev/sda ,/dev/sda3 ,g'
        cat << 'EOF' > grub.cfg
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

menuentry 'Open Firmware' --id openfirmware {
        exit
}
menuentry 'Reboot' --id reboot {
        reboot
}
menuentry 'Power Off' --id poweroff {
        halt
}
EOF

        # Create a bootstrap image.
        truncate --size=$boot_size boot.img
        hformat -f -l Bootstrap boot.img 0
        hmount boot.img 0
        hcopy -r grub.cfg :grub.cfg
        hcopy -r grub.elf :grub.elf
        hcopy -r kargs.env :kargs_a
        hcopy -r vmlinux :linux_a
        test -s initrd.img && hcopy -r initrd.img :initrd_a
        hattrib -c UNIX -t tbxi :grub.elf
        hattrib -b :
        humount

        # Format an Apple Partition Map image, and write its file systems.
        truncate --size=$image_size apm.img
        {
                echo i '' \
                    C $(( base += length )) $(( length = boot_size / bs )) bootstrap Apple_Bootstrap
                for (( i = 1 ; i <= slots ; i++ ))
                do echo -e c $(( base += length )) $(( length = slot_size / bs )) "ROOT-\\x4$i"
                done
                echo \
                    c $(( base += length )) $(( length = (image_size / bs) - base )) var \
                    w y q
        } | tr ' ' '\n' | mac-fdisk apm.img
        dd bs=$bs conv=notrunc if=boot.img of=apm.img seek=64
        dd bs=$bs conv=notrunc if=final.img of=apm.img seek=$(( 64 + boot_size / bs ))
        mkfs.ext4 -E offset=$(( 64 * bs + boot_size + slot_size * slots )) \
            -F -L var -m 0 -U "${options[var_uuid]}" apm.img
fi

function write_system_kernel_config() if opt bootable
then
        cat << 'EOF' >> /etc/kernel/config.d/qemu.config.disabled
# TARGET HARDWARE: QEMU
## QEMU default graphics
CONFIG_DRM_BOCHS=m
## QEMU default disk
CONFIG_ATA_PIIX=y
## QEMU default serial port
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
EOF
        cat >> /etc/kernel/config.d/system.config
fi << 'EOF'
# Show initialization messages.
CONFIG_PRINTK=y
# Support adding swap space.
CONFIG_SWAP=y
# Support ext2/ext3/ext4 (which is not included for read-only images).
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_FS_SECURITY=y
CONFIG_EXT4_USE_FOR_EXT2=y
# Support HFS for kernel/bootloader updates.
CONFIG_MISC_FILESYSTEMS=y
CONFIG_HFS_FS=m
# Support encrypted partitions.
CONFIG_BLK_DEV_DM=y
CONFIG_DM_CRYPT=m
CONFIG_DM_INTEGRITY=m
# Support FUSE.
CONFIG_FUSE_FS=m
# Support running virtual machines in QEMU.
CONFIG_VIRTUALIZATION=y
# Support registering handlers for other architectures.
CONFIG_BINFMT_MISC=y
# Support running containers in nspawn.
CONFIG_POSIX_MQUEUE=y
CONFIG_SYSVIPC=y
CONFIG_IPC_NS=y
CONFIG_NET_NS=y
CONFIG_PID_NS=y
CONFIG_USER_NS=y
CONFIG_UTS_NS=y
# Support mounting disk images.
CONFIG_BLK_DEV=y
CONFIG_BLK_DEV_LOOP=y
# Provide a fancy framebuffer console.
CONFIG_FB=y
CONFIG_TTY=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_VGA_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_DRM_FBDEV_EMULATION=y
# Support basic nftables firewall options.
CONFIG_NETFILTER=y
CONFIG_NF_CONNTRACK=y
CONFIG_NF_TABLES=y
CONFIG_NF_TABLES_IPV4=y
CONFIG_NF_TABLES_IPV6=y
CONFIG_NFT_CT=y
## Support translating iptables to nftables.
CONFIG_NFT_COMPAT=y
CONFIG_NETFILTER_XTABLES=y
CONFIG_NETFILTER_XT_MATCH_STATE=y
# Support some optional systemd functionality.
CONFIG_COREDUMP=y
CONFIG_MAGIC_SYSRQ=y
CONFIG_NET_SCHED=y
CONFIG_NET_SCH_DEFAULT=y
CONFIG_NET_SCH_FQ_CODEL=y
# TARGET HARDWARE: Apple Mac mini (first generation)
CONFIG_FB_OF=y
CONFIG_PPC_CHRP=y
CONFIG_PPC_OF_BOOT_TRAMPOLINE=y
## Bundle firmware
CONFIG_EXTRA_FIRMWARE="radeon/R200_cp.bin"
## PowerPC G4 CPU
CONFIG_PPC_BOOK3S_32=y
CONFIG_PPC_PMAC=y
CONFIG_G4_CPU=y
CONFIG_KVM_BOOK3S_32=y
## 1GiB RAM
CONFIG_HIGHMEM=y
## PMU
CONFIG_MACINTOSH_DRIVERS=y
CONFIG_ADB_PMU=y
## NVRAM
CONFIG_NVRAM=y
## Disks
CONFIG_ATA=y
CONFIG_ATA_SFF=y
CONFIG_ATA_BMDMA=y
CONFIG_PATA_MACIO=y
## UJ-835-C DVD drive (with CD FS)
CONFIG_BLK_DEV_SR=y
CONFIG_ISO9660_FS=m
CONFIG_JOLIET=y
## ATI Radeon 9200
CONFIG_AGP=y
CONFIG_AGP_UNINORTH=y
CONFIG_DRM=y
CONFIG_DRM_RADEON=y
## Toonie audio
CONFIG_SOUND=y
CONFIG_SND=y
CONFIG_SND_AOA=y
CONFIG_SND_AOA_FABRIC_LAYOUT=y
CONFIG_SND_AOA_TOONIE=y
CONFIG_HIGH_RES_TIMERS=y
CONFIG_SND_HRTIMER=y
## Firewire support
CONFIG_FIREWIRE=y
CONFIG_FIREWIRE_OHCI=y
## USB support
CONFIG_USB_SUPPORT=y
CONFIG_USB=y
CONFIG_USB_DEFAULT_PERSIST=y
CONFIG_USB_PCI=y
CONFIG_USB_EHCI_HCD=y
CONFIG_USB_EHCI_HCD_PCI=y
CONFIG_USB_OHCI_HCD=y
CONFIG_USB_OHCI_HCD_PCI=y
## Ethernet
CONFIG_NETDEVICES=y
CONFIG_ETHERNET=y
CONFIG_NET_VENDOR_SUN=y
CONFIG_SUNGEM=y
## Input
CONFIG_HID=y
CONFIG_HID_BATTERY_STRENGTH=y
CONFIG_HID_GENERIC=y
CONFIG_INPUT=y
CONFIG_INPUT_EVDEV=y
## USB storage
CONFIG_SCSI=y
CONFIG_BLK_DEV_SD=y
CONFIG_USB_STORAGE=y
CONFIG_USB_UAS=y
## Optional USB devices
CONFIG_SND_USB=y
CONFIG_HID_GYRATION=m   # wireless mouse and keyboard
CONFIG_SND_USB_AUDIO=m  # headsets
CONFIG_USB_ACM=m        # fit-PC status LED
CONFIG_USB_HID=m        # mice and keyboards
EOF
