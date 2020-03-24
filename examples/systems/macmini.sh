# This is an example Gentoo build for a specific target system, the first
# generation Apple Mac mini (based on the PowerPC G4 CPU).  It demonstrates
# cross-compiling for a 32-bit PPC device and generating a bootable disk image
# for a non-UEFI platform.  It can be booted from USB at the Open Firmware
# prompt (by holding Command-Option-O-F while booting or by setting the NVRAM
# variable auto-boot?=false) with the command "boot usb0/disk:2,::tbxi".
#
# Since this is a non-UEFI system that can't have a Secure Boot signature, it
# might as well skip verity to save CPU cycles.  It should also avoid squashfs
# compression if storage space isn't an issue to save more cycles.  SELinux
# should be skipped since it's still unenforceable, and this isn't the platform
# for working on improving support.

options+=(
        [arch]=powerpc   # Target PowerPC G4 CPUs.
        [distro]=gentoo  # Use Gentoo to build this image from source.
        [bootable]=1     # Build a kernel for this system.
        [networkd]=1     # Let systemd manage the network configuration.
        [read_only]=1    # Use an efficient packed read-only file system.
        [squash]=1       # Compress the image while experimenting.
        [uefi]=          # This platform does not support UEFI.
)

packages+=(
        # Utilities
        app-arch/tar
        app-arch/unzip
        app-shells/bash
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
        media-sound/pulseaudio
        x11-apps/xev
        x11-apps/xrandr
        x11-base/xorg-server
        x11-terms/xterm
        x11-wm/windowmaker
)

packages_buildroot+=(
        # The target hardware requires firmware.
        sys-kernel/linux-firmware
)

# Support automatically building a bootable APM disk image in this script.
function initialize_buildroot() {
        echo 'GRUB_PLATFORMS="ieee1275"' >> "$buildroot/etc/portage/make.conf"
        packages_buildroot+=(sys-boot/grub sys-fs/hfsutils sys-fs/mac-fdisk)
}

function customize_buildroot() {
        local -r portage="$buildroot/usr/${options[host]}/etc/portage"

        # Tune compilation for the PowerPC G4.
        $sed -i \
            -e '/^COMMON_FLAGS=/s/[" ]*$/ -mcpu=7450 -maltivec -mabi=altivec -ftree-vectorize&/' \
            "$portage/make.conf"
        echo -e 'CPU_FLAGS_PPC="altivec"\nUSE="$USE altivec ppcsha1"' >> "$portage/make.conf"
        ## The ffmpeg cross-compilation needs hand-holding here.
        echo -e 'EXTRA_FFMPEG_CONF="--cpu=g4"\nbigendian="yes"' >> "$portage/env/ffmpeg.conf"
        echo 'media-video/ffmpeg ffmpeg.conf' >> "$portage/package.env/ffmpeg.conf"

        # Use the RV280 driver for the ATI Radeon 9200 graphics processor.
        echo 'VIDEO_CARDS="radeon r200"' >> "$portage/make.conf"

        # Enable general system settings.
        echo >> "$portage/make.conf" 'USE="$USE' \
            curl dbus gcrypt gdbm git gmp gnutls gpg libnotify libxml2 mpfr nettle ncurses pcre2 readline sqlite udev uuid \
            fribidi icu idn libidn2 nls unicode \
            apng gif imagemagick jbig jpeg jpeg2k png svg webp xpm \
            alsa libsamplerate mp3 ogg pulseaudio sndfile sound speex theora vorbis vpx \
            bzip2 gzip lz4 lzma lzo xz zlib zstd \
            acl caps cracklib fprint hardened pam seccomp smartcard xattr xcsecurity \
            acpi dri gallium kms libglvnd libkms opengl usb uvm vaapi vdpau wps \
            cairo gtk3 pango plymouth X xa xcb xft xinerama xkb xorg xrandr xvmc \
            branding ipv6 jit lto offensive threads \
            dynamic-loading hwaccel postproc secure-delete startup-notification toolkit-scroll-bars user-session wide-int \
            -cups -debug -emacs -fortran -geolocation -gtk -gtk2 -introspection -llvm -oss -perl -python -sendmail -tcpd -vala'"'

        # Build less useless stuff on the host from bad dependencies.
        echo >> "$buildroot/etc/portage/make.conf" 'USE="$USE' \
            -cups -debug -emacs -fortran -gallium -geolocation -gtk -gtk2 -introspection -llvm -oss -perl -python -sendmail -tcpd -vala'"'

        # Accept the sshfs version that is stable everywhere else.
        echo 'net-fs/sshfs *' >> "$portage/package.accept_keywords/sshfs.conf"

        # Install QEMU to run graphical virtual machines and Intel programs.
        packages+=(app-emulation/qemu sys-firmware/seabios)
        echo -e 'QEMU_SOFTMMU_TARGETS="ppc"\nQEMU_USER_TARGETS="i386"' >> "$portage/make.conf"
        $cat << 'EOF' >> "$portage/package.accept_keywords/qemu.conf"
app-emulation/qemu *
sys-apps/dtc *
sys-firmware/seabios *
virtual/libusb *
EOF
        $cat << 'EOF' >> "$portage/package.use/qemu.conf"
app-emulation/qemu gtk static-user
dev-libs/glib static-libs
dev-libs/libpcre static-libs
sys-apps/attr static-libs
sys-libs/zlib static-libs
EOF

        # Include a graphical Emacs.
        fix_package emacs
        packages+=(app-editors/emacs)
        echo 'USE="$USE emacs gzip-el xwidgets"' >> "$portage/make.conf"
        $cat << 'EOF' >> "$portage/package.use/emacs.conf"
app-editors/emacs gtk
dev-util/desktop-file-utils -emacs
dev-vcs/git -emacs
EOF

        # Configure the kernel by only enabling this system's settings.
        write_minimal_system_kernel_configuration > "$output/config"
        enter /usr/bin/make -C /usr/src/linux allnoconfig ARCH=powerpc \
            CROSS_COMPILE="${options[host]}-" KCONFIG_ALLCONFIG=/wd/config V=1
}

function customize() {
        drop_debugging
        drop_development
        store_home_on_var +root

        echo macmini > root/etc/hostname

        # Drop extra unused paths.
        exclude_paths+=(
                usr/lib/firmware
                usr/local
        )

        # Support running Intel containers.
        echo > root/usr/lib/binfmt.d/qemu-i386.conf \
            ':qemu-i386:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x03\x00:\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-i386:'
        echo > root/usr/lib/binfmt.d/qemu-i486.conf \
            ':qemu-i486:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x06\x00:\xff\xff\xff\xff\xff\xfe\xfe\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-i386:'

        # Have PulseAudio default to ALSA output, and don't suspend devices.
        sed -i \
            -e '/load-module module-alsa-sink/s/^[# ]*//' \
            -e 's/^load-module .*suspend/#&/' \
            root/etc/pulse/default.pa
        cat << 'EOF' > root/etc/asound.conf
pcm.!default {
 type hw
 card 0
}
ctl.!default {
 type hw
 card 0
}
EOF

        # Define how to mount the bootstrap partition, but leave it unmounted.
        mkdir root/boot ; echo >> root/etc/fstab PARTLABEL=bootstrap \
            /boot hfs defaults,noatime,noauto,nodev,noexec,nosuid

        # Try to use a persistent /var partition from a plain file system UUID.
        echo "UUID=${options[var_uuid]:=$(</proc/sys/kernel/random/uuid)}" \
            /var ext4 defaults,nodev,nofail,nosuid >> root/etc/fstab
}

# Override the executable image function as a hack to produce a full disk image
# for convenience since APM is incompatible with an executable file header.
function produce_executable_image() if opt bootable
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
            -e 's/ *\(dm-mod.create=\|DVR=\)"\([^"]*\)".*/\ndmsetup=\1\2/' \
            -e 's,/dev/sda ,/dev/sda3 ,g'
        cat << 'EOF' > grub.cfg
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

        # Write a script with an example boot command to test with QEMU.
        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu
exec qemu-system-ppc \
    -machine mac99,via=pmu -cpu g4 -m 1G -vga std -nic user,model=sungem \
    -prom-env 'boot-device=hd:2,grub.elf' \
    -drive file="${IMAGE:-apm.img}",format=raw,media=disk \
    "$@"
EOF
fi

function write_minimal_system_kernel_configuration() { $cat "$output/config.base" - << 'EOF' ; }
# Show initialization messages.
CONFIG_PRINTK=y
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
# Build basic firewall filter options.
CONFIG_NETFILTER=y
CONFIG_NF_CONNTRACK=y
CONFIG_NETFILTER_XT_MATCH_STATE=y
CONFIG_IP_NF_IPTABLES=y
CONFIG_IP_NF_FILTER=y
CONFIG_IP6_NF_IPTABLES=y
CONFIG_IP6_NF_FILTER=y
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
CONFIG_HID_GYRATION=m  # wireless mouse and keyboard
CONFIG_USB_ACM=m       # fit-PC status LED
CONFIG_USB_HID=m       # mice and keyboards
# TARGET HARDWARE: QEMU
## QEMU default graphics
CONFIG_DRM_BOCHS=m
## QEMU default disk
CONFIG_ATA_PIIX=y
## QEMU default serial port
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
EOF
