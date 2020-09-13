# This is an example Gentoo build for a specific target system, the fit-PC Slim
# (based on the AMD Geode LX 800 CPU).  It demonstrates cross-compiling to an
# uncommon instruction set with plenty of other hardware components that are
# specific to that platform.  Sample bootloader files are prepared that allow
# booting this system from a GPT/UEFI-formatted disk.

options+=(
        [arch]=i686      # Target AMD Geode LX CPUs.  (Note i686 has no NOPL.)
        [distro]=gentoo  # Use Gentoo to build this image from source.
        [bootable]=1     # Build a kernel for this system.
        [monolithic]=1   # Build all boot-related files into the kernel image.
        [networkd]=1     # Let systemd manage the network configuration.
        [squash]=1       # Use a highly compressed file system to save space.
        [uefi]=          # This platform does not support UEFI.
        [verity_sig]=1   # Require all verity root hashes to be verified.
)

packages+=(
        # Utilities
        app-arch/cpio
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
        net-wireless/wireless-regdb
        sys-kernel/linux-firmware
)

# Build unused GRUB images for this platform for separate manual installation.
function initialize_buildroot() {
        echo 'GRUB_PLATFORMS="pc"' >> "$buildroot/etc/portage/make.conf"
        packages_buildroot+=(sys-boot/grub)
}

function customize_buildroot() {
        local -r portage="$buildroot/usr/${options[host]}/etc/portage"

        # Tune compilation for the AMD Geode LX 800.
        $sed -i \
            -e '/^COMMON_FLAGS=/s/[" ]*$/ -march=geode -mmmx -m3dnow -ftree-vectorize&/' \
            "$portage/make.conf"
        echo 'CPU_FLAGS_X86="3dnow 3dnowext mmx mmxext"' >> "$portage/make.conf"
        echo 'ABI_X86="32 64"' >> "$buildroot/etc/portage/make.conf"  # Portage is bad.

        # Use the Geode video driver.
        echo -e 'USE="$USE ztv"\nVIDEO_CARDS="geode"' >> "$portage/make.conf"

        # Enable general system settings.
        echo >> "$portage/make.conf" 'USE="$USE' \
            curl dbus elfutils gcrypt gdbm git gmp gnutls gpg http2 libnotify libxml2 mpfr nettle ncurses pcre2 readline sqlite udev uuid xml \
            bidi fribidi harfbuzz icu idn libidn2 nls truetype unicode \
            apng gif imagemagick jbig jpeg jpeg2k png svg webp xpm \
            alsa flac libsamplerate mp3 ogg pulseaudio sndfile sound speex vorbis \
            a52 aom dav1d dvd libaom mpeg theora vpx x265 \
            bzip2 gzip lz4 lzma lzo xz zlib zstd \
            acl caps cracklib fprint hardened pam seccomp smartcard xattr xcsecurity \
            acpi dri gallium kms libglvnd libkms opengl usb uvm vaapi vdpau wps \
            cairo gtk3 libdrm pango plymouth X xa xcb xft xinerama xkb xorg xrandr xvmc \
            branding ipv6 jit lto offensive pcap threads \
            dynamic-loading hwaccel postproc startup-notification toolkit-scroll-bars user-session wide-int \
            -cups -debug -emacs -fortran -gallium -geolocation -gtk -gtk2 -introspection -llvm -oss -perl -python -sendmail -tcpd -vala'"'

        # Build less useless stuff on the host from bad dependencies.
        echo >> "$buildroot/etc/portage/make.conf" 'USE="$USE' \
            -cups -debug -emacs -fortran -gallium -geolocation -gtk -gtk2 -introspection -llvm -oss -perl -python -sendmail -tcpd -vala -X'"'

        # Install Firefox.
        fix_package firefox
        packages+=(www-client/firefox)

        # Install Emacs as a terminal application.
        fix_package emacs
        packages+=(app-editors/emacs)

        # Configure the kernel by only enabling this system's settings.
        write_minimal_system_kernel_configuration > "$output/config"
        enter /usr/bin/make -C /usr/src/linux allnoconfig ARCH=x86 \
            CROSS_COMPILE="${options[host]}-" KCONFIG_ALLCONFIG=/wd/config V=1
}

function customize() {
        drop_debugging
        drop_development
        store_home_on_var +root

        echo fitpc > root/etc/hostname

        # Drop extra unused paths.
        exclude_paths+=(
                usr/lib/firmware
                usr/local
        )

        # Start the wireless interface if it is configured.
        mkdir -p root/usr/lib/systemd/system/network.target.wants
        ln -fns ../wpa_supplicant-nl80211@.service \
            root/usr/lib/systemd/system/network.target.wants/wpa_supplicant-nl80211@wlp0s15f5u4.service

        # Include a mount point for a writable boot partition.
        mkdir root/boot

        create_gpt_bios_grub_files
}

# Make our own BIOS GRUB files for booting from a GPT disk.  Formatting a disk
# with fdisk forces the first partition to begin at least 1MiB from the start
# of the disk, which is the usual size of the boot partition that GRUB requires
# to install on GPT.  Reconfigure GRUB's boot.img and diskboot.img so the core
# image can be booted when written directly after the GPT.
#
# Install these files with the following commands:
#       dd bs=512 conv=notrunc if=core.img of="$disk" seek=34
#       dd bs=512 conv=notrunc if=boot.img of="$disk"
function create_gpt_bios_grub_files() if opt bootable
then
        # Take the normal boot.img, and make it a protective MBR.
        cp -pt . /usr/lib/grub/i386-pc/boot.img
        dd bs=1 conv=notrunc count=64 of=boot.img seek=446 \
            if=<(echo -en '\0\0\x02\0\xEE\xFF\xFF\xFF\x01\0\0\0\xFF\xFF\xFF\xFF' ; exec cat /dev/zero)

        # Create a core.img with preloaded modules to read /grub.cfg on an ESP.
        grub-mkimage \
            --compression=none \
            --format=i386-pc \
            --output=core.img \
            --prefix='(hd0,gpt1)' \
            biosdisk fat halt linux loadenv minicmd normal part_gpt reboot test

        # Set boot.img and diskboot.img to load immediately after the GPT.
        dd bs=1 conv=notrunc count=1 if=<(echo -en '\x22') of=boot.img seek=92
        dd bs=1 conv=notrunc count=1 if=<(echo -en '\x23') of=core.img seek=500
fi

function write_minimal_system_kernel_configuration() { $cat "$output/config.base" - << 'EOF' ; }
# Show initialization messages.
CONFIG_PRINTK=y
# Support adding swap space.
CONFIG_SWAP=y
# Support ext2/ext3/ext4 (which is not included for read-only images).
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_FS_SECURITY=y
CONFIG_EXT4_USE_FOR_EXT2=y
# Support VFAT (which is not included when not using UEFI).
CONFIG_VFAT_FS=m
CONFIG_FAT_DEFAULT_UTF8=y
CONFIG_NLS=m
CONFIG_NLS_DEFAULT="utf8"
CONFIG_NLS_CODEPAGE_437=m
CONFIG_NLS_ISO8859_1=m
CONFIG_NLS_UTF8=m
# Support mirroring disks via RAID.
CONFIG_MD=y
CONFIG_BLK_DEV_MD=y
CONFIG_MD_AUTODETECT=y
CONFIG_MD_RAID1=y
# Support encrypted partitions.
CONFIG_BLK_DEV_DM=y
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
# Support basic nftables firewall options.
CONFIG_NETFILTER=y
CONFIG_NF_CONNTRACK=y
CONFIG_NF_TABLES=y
CONFIG_NF_TABLES_IPV4=y
CONFIG_NF_TABLES_IPV6=y
CONFIG_NFT_COUNTER=y
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
# TARGET HARDWARE: fit-PC Slim
CONFIG_PCI=y
CONFIG_PCI_MSI=y
CONFIG_SCx200=y
## Bundle firmware
CONFIG_EXTRA_FIRMWARE="regulatory.db regulatory.db.p7s rt73.bin"
## Geode LX 800 CPU
CONFIG_MGEODE_LX=y
CONFIG_CPU_SUP_AMD=y
CONFIG_MICROCODE_AMD=y
## AES processor
CONFIG_CRYPTO_HW=y
CONFIG_CRYPTO_DEV_GEODE=y
## Random number generator
CONFIG_HW_RANDOM=y
CONFIG_HW_RANDOM_GEODE=y
## Disks
CONFIG_ATA=y
CONFIG_ATA_SFF=y
CONFIG_ATA_BMDMA=y
CONFIG_PATA_CS5536=y
#CONFIG_BLK_DEV_CS5536=y  # Legacy IDE version
## Graphics
CONFIG_FB_GEODE=y
CONFIG_FB_GEODE_LX=y
CONFIG_DEVMEM=y           # Required by the X video driver
CONFIG_X86_IOPL_IOPERM=y  # Required by the X video driver
CONFIG_X86_MSR=y          # Required by the X video driver
## Audio
CONFIG_SOUND=y
CONFIG_SND=y
CONFIG_SND_PCI=y
CONFIG_SND_CS5535AUDIO=y
## USB support
CONFIG_USB_SUPPORT=y
CONFIG_USB=y
CONFIG_USB_DEFAULT_PERSIST=y
CONFIG_USB_PCI=y
CONFIG_USB_GADGET=y
CONFIG_USB_AMD5536UDC=y
## Serial support
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_RUNTIME_UARTS=2
## Ethernet
CONFIG_NETDEVICES=y
CONFIG_ETHERNET=y
CONFIG_NET_VENDOR_REALTEK=y
CONFIG_8139TOO=y
## Wifi
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_MAC80211_RC_MINSTREL=y
CONFIG_WLAN=y
CONFIG_WLAN_VENDOR_RALINK=y
CONFIG_RT2X00=y
CONFIG_RT73USB=y
## High-resolution timers
CONFIG_MFD_CS5535=y
CONFIG_CS5535_MFGPT=y
CONFIG_CS5535_CLOCK_EVENT_SRC=y
## Watchdog device
CONFIG_WATCHDOG=y
CONFIG_GEODE_WDT=y
## GPIO
CONFIG_GPIOLIB=y
CONFIG_GPIO_CS5535=y
## NAND controller
CONFIG_MTD=y
CONFIG_MTD_RAW_NAND=y
CONFIG_MTD_NAND_CS553X=y
## I2C
CONFIG_I2C=y
CONFIG_SCx200_ACB=y
## Input
CONFIG_HID=y
CONFIG_HID_BATTERY_STRENGTH=y
CONFIG_HID_GENERIC=y
CONFIG_INPUT=y
CONFIG_INPUT_EVDEV=y
## USB storage
CONFIG_USB_OHCI_HCD=y
CONFIG_USB_OHCI_HCD_PCI=y
CONFIG_USB_EHCI_HCD=y
CONFIG_USB_EHCI_HCD_PCI=y
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
