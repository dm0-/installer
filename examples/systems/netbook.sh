# This is an example Gentoo build for a specific target system, the Sylvania
# SYNET07526-Z netbook (based on the ARM ARM926EJ-S CPU).  It demonstrates
# cross-compiling for a 32-bit ARM9 device and generating a U-Boot script that
# starts Linux.  The vmlinuz.uimg and scriptcmd files must be written to the
# /script directory on the first FAT-formatted MS-DOS partition of an SD card,
# which will be booted automatically when starting the system.
#
# Since this is a non-UEFI system that can't have a Secure Boot signature, it
# might as well skip verity to save CPU cycles.  It should also avoid squashfs
# compression if storage space isn't an issue to save more cycles.  SELinux
# should be skipped since it's still unenforceable, and this isn't the platform
# for working on improving support.

options+=(
        [arch]=armv5tel  # Target ARM ARM926EJ-S CPUs.
        [distro]=gentoo  # Use Gentoo to build this image from source.
        [bootable]=1     # Build a kernel for this system.
        [networkd]=1     # Let systemd manage the network configuration.
        [read_only]=1    # Use an efficient packed read-only file system.
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

        # Graphics
        x11-apps/xev
        x11-apps/xrandr
        x11-base/xorg-server
        x11-terms/xterm
        x11-wm/twm
)

# Support building U-Boot images and GRUB for the bootloader.
function initialize_buildroot() {
        echo 'GRUB_PLATFORMS="uboot"' >> "$buildroot/etc/portage/make.conf"
        packages_buildroot+=(dev-embedded/u-boot-tools sys-boot/grub)
}

function customize_buildroot() {
        local -r portage="$buildroot/usr/${options[host]}/etc/portage"

        # Tune compilation for the ARM ARM926EJ-S.
        $sed -i \
            -e '/^COMMON_FLAGS=/s/[" ]*$/ -march=armv5te -mtune=arm926ej-s -ftree-vectorize&/' \
            "$portage/make.conf"
        echo 'CPU_FLAGS_ARM="edsp thumb v4 v5"' >> "$portage/make.conf"

        # Fall back to the fbdev driver for graphical sessions.
        echo 'VIDEO_CARDS="fbdev"' >> "$portage/make.conf"

        # Enable general system settings.
        echo >> "$portage/make.conf" 'USE="$USE' twm \
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
            -cups -debug -emacs -fortran -gallium -geolocation -gtk -gtk2 -introspection -llvm -oss -perl -python -sendmail -tcpd -vala -X'"'

        # Install Emacs as a terminal application.
        fix_package emacs
        packages+=(app-editors/emacs)
        echo 'USE="$USE emacs gzip-el"' >> "$portage/make.conf"
        $cat << 'EOF' >> "$portage/package.use/emacs.conf"
app-editors/emacs -X
dev-util/desktop-file-utils -emacs
dev-vcs/git -emacs
EOF

        # Fix the dumb libgpg-error build process for this target.
        $mkdir -p "$portage/patches/dev-libs/libgpg-error"
        $cat << EOF > "$portage/patches/dev-libs/libgpg-error/cross.patch"
diff --git a/src/syscfg/lock-obj-pub.${options[arch]}-unknown-linux-gnueabi.h b/src/syscfg/lock-obj-pub.${options[arch]}-unknown-linux-gnueabi.h
new file mode 120000
index 0000000..71a9292
--- /dev/null
+++ b/src/syscfg/lock-obj-pub.${options[arch]}-unknown-linux-gnueabi.h
@@ -0,0 +1 @@
+lock-obj-pub.arm-unknown-linux-gnueabi.h
\ No newline at end of file
EOF

        # Fix the screen contrast.
        $sed -i -e 's/fbi->contrast = 0x10/fbi->contrast = 0x80/g' \
            "$buildroot/usr/src/linux/drivers/video/fbdev/wm8505fb.c"

        # Configure the kernel by only enabling this system's settings.
        write_minimal_system_kernel_configuration > "$output/config"
        enter /usr/bin/make -C /usr/src/linux allnoconfig ARCH=arm \
            CROSS_COMPILE="${options[host]}-" KCONFIG_ALLCONFIG=/wd/config V=1
}

function customize() {
        drop_debugging
        drop_development
        store_home_on_var +root

        echo netbook > root/etc/hostname

        # Drop extra unused paths.
        exclude_paths+=(
                usr/lib/firmware
                usr/local
        )
}

# Override the UEFI function as a hack to produce the U-Boot files.
function produce_uefi_exe() if opt bootable
then
        local -r dtb=/usr/src/linux/arch/arm/boot/dts/wm8505-ref.dtb

        # Build the system's device tree blob.
        make -C /usr/src/linux "${dtb##*/}" \
            ARCH=arm CROSS_COMPILE="${options[host]}-" V=1

        # Build a U-Boot kernel image with the bundled DTB.
        local -r data=$(mktemp)
        cat /usr/src/linux/arch/arm/boot/{zImage,dts/wm8505-ref.dtb} > "$data"
        mkimage -A arm -C none -O linux -T kernel -a 0x8000 -d "$data" -e 0x8000 -n Linux vmlinuz.uimg

        # Write a boot script to start the kernel.
        mkimage -A arm -C none -O linux -T script -d /dev/stdin -n 'Boot script' scriptcmd << EOF
lcdinit
fatload mmc 0 0 /script/vmlinuz.uimg
setenv bootargs $(<kernel_args.txt) rootwait
bootm 0
EOF

        # Build an ARM GRUB image that U-Boot can use.  (experiment)
        grub-mkimage \
            --compression=none \
            --format=arm-uboot \
            --output=grub.uimg \
            --prefix= \
            fat halt linux loadenv minicmd normal part_gpt reboot test
fi

function write_minimal_system_kernel_configuration() { $cat "$output/config.base" - << 'EOF' ; }
# Show initialization messages.
CONFIG_PRINTK=y
# Support ext2/ext3/ext4 (which is not included for read-only images).
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_FS_SECURITY=y
CONFIG_EXT4_USE_FOR_EXT2=y
# Support encrypted partitions.
CONFIG_DM_CRYPT=m
CONFIG_DM_INTEGRITY=m
# Support FUSE.
CONFIG_FUSE_FS=m
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
# TARGET HARDWARE: Sylvania SYNET07526-Z
CONFIG_AEABI=y
CONFIG_ARM_APPENDED_DTB=y
CONFIG_ARM_ATAG_DTB_COMPAT=y
## ARM ARM926EJ-S
CONFIG_ARM_THUMB=y
## SoC WM8505
CONFIG_ARCH_WM8505=y
CONFIG_FB_WM8505=y
CONFIG_FB_WMT_GE_ROPS=y
CONFIG_I2C=y
CONFIG_I2C_WMT=y
CONFIG_PINCTRL_WM8505=y
## USB support
CONFIG_USB_SUPPORT=y
CONFIG_USB=y
CONFIG_USB_DEFAULT_PERSIST=y
CONFIG_USB_EHCI_HCD=y
CONFIG_USB_EHCI_HCD_PLATFORM=y
CONFIG_USB_UHCI_HCD=y
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
## Memory card
CONFIG_MMC=y
CONFIG_MMC_BLOCK=y
CONFIG_MMC_BLOCK_MINORS=32
CONFIG_MMC_WMT=y
## RTC
CONFIG_RTC_CLASS=y
CONFIG_RTC_DRV_VT8500=y
## Optional USB devices
CONFIG_HID_GYRATION=m  # wireless mouse and keyboard
CONFIG_USB_ACM=m       # fit-PC status LED
CONFIG_USB_HID=m       # mice and keyboards
EOF
