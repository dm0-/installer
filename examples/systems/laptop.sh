# SPDX-License-Identifier: GPL-3.0-or-later
# This is an example Gentoo build for a specific target system, the Lenovo
# Thinkpad P1 (Gen 2).  It demonstrates native compilation where the build
# system is the target system, which uses automatic detection of CPU features.

options+=(
        [distro]=gentoo  # Use Gentoo to build this image from source.
        [gpt]=1          # Generate a VM disk image for fast testing.
        [networkd]=1     # Let systemd manage the network configuration.
        [nvme]=1         # Support root on an NVMe disk.
        [selinux]=1      # Load a targeted SELinux policy in permissive mode.
        [squash]=1       # Use a highly compressed file system to save space.
        [uefi]=1         # Create a UEFI executable that boots into this image.
        [verity_sig]=1   # Require all verity root hashes to be verified.
)

packages+=(
        # Utilities
        app-arch/cpio
        app-arch/tar
        app-arch/unzip
        app-editors/emacs
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

        # Host
        app-emulation/qemu

        # Graphics
        lxde-base/lxdm
        media-sound/pavucontrol
        media-video/pipewire
        x11-apps/xev
        x11-base/xorg-server
        xfce-base/xfce4-meta

        # Browser
        www-client/firefox
)

packages_buildroot+=(
        # Automatically generate the supported instruction set flags.
        app-portage/cpuid2cpuflags

        # The target hardware requires firmware.
        net-wireless/wireless-regdb
        sys-firmware/intel-microcode
        sys-kernel/linux-firmware
)

function initialize_buildroot() {
        local -r portage="$buildroot/usr/${options[host]}/etc/portage"

        # Assume the build system is the target, and tune compilation for it.
        $sed -i \
            -e '/^COMMON_FLAGS=/s/[" ]*$/ -march=native -ftree-vectorize&/' \
            "$portage/make.conf"
        echo 'RUSTFLAGS="-C target-cpu=native"' >> "$portage/make.conf"

        # Use the latest NVIDIA drivers.
        echo -e 'USE="$USE kmod"\nVIDEO_CARDS="nvidia"' >> "$portage/make.conf"
        echo -e 'media-libs/nv-codec-headers\nx11-drivers/nvidia-drivers' >> "$portage/package.accept_keywords/nvidia.conf"
        echo 'x11-drivers/nvidia-drivers NVIDIA-r2' >> "$portage/package.license/nvidia.conf"
        echo 'x11-drivers/nvidia-drivers -tools' >> "$portage/package.use/nvidia.conf"

        # Enable general system settings.
        echo >> "$portage/make.conf" 'USE="$USE' \
            berkdb dbus elfutils emacs gdbm git glib json libnotify libxml2 ncurses pcre2 readline sqlite udev uuid xml \
            bidi fontconfig fribidi harfbuzz icu idn libidn2 nls truetype unicode \
            apng exif gif imagemagick jbig jpeg jpeg2k png svg tiff webp xpm \
            a52 alsa cdda faad flac libcanberra libsamplerate mp3 ogg opus pulseaudio sndfile sound speex vorbis \
            aacs aom bdplus bluray cdio dav1d dvd ffmpeg libaom mpeg theora vpx x265 \
            brotli bzip2 gzip lz4 lzma lzo snappy xz zlib zstd \
            cryptsetup gcrypt gmp gnutls gpg mpfr nettle \
            curl http2 ipv6 libproxy modemmanager networkmanager wifi wps \
            acl caps cracklib fprint hardened pam policykit seccomp smartcard xattr xcsecurity \
            acpi dri gallium gusb kms libglvnd libkms opengl upower usb uvm vaapi vdpau \
            cairo colord gtk gtk3 gui lcms libdrm pango uxa wnck X xa xcb xft xinerama xkb xorg xrandr xvmc xwidgets \
            aio branding haptic jit lto offensive pcap system-info threads udisks utempter vte \
            dynamic-loading gzip-el hwaccel postproc repart startup-notification toolkit-scroll-bars user-session wide-int \
            -cups -dbusmenu -debug -fortran -geolocation -gstreamer -introspection -llvm -oss -perl -python -sendmail -tcpd -vala \
            -gui -networkmanager -repart -wifi'"'

        # Install VLC.
        fix_package vlc
        packages+=(media-video/vlc)
}

function customize_buildroot() {
        # Enable flags for instruction sets supported by this CPU.
        cpuid2cpuflags | sed -n 's/^\([^ :]*\): \(.*\)/\1="\2"/p' >> "/usr/${options[host]}/etc/portage/make.conf"

        # Build less useless stuff on the host from bad dependencies.
        echo >> /etc/portage/make.conf 'USE="$USE' \
            -cups -debug -emacs -fortran -geolocation -gstreamer -introspection -llvm -oss -perl -python -sendmail -tcpd -vala -X'"'

        # Configure the kernel by only enabling this system's settings.
        write_system_kernel_config
}

function customize() {
        double_display_scale
        drop_development
        store_home_on_var +root

        echo laptop > root/etc/hostname

        # Drop extra unused paths.
        exclude_paths+=(
                usr/lib/firmware
                usr/local
                usr/share/qemu/'*'{aarch,arm,hppa,ppc,riscv,s390,sparc}'*'
        )

        # Start the wireless interface if it is configured.
        mkdir -p root/usr/lib/systemd/system/network.target.wants
        ln -fns ../wpa_supplicant-nl80211@.service \
            root/usr/lib/systemd/system/network.target.wants/wpa_supplicant-nl80211@wlp82s0.service

        # Sign the out-of-tree kernel modules due to required signatures.
        for module in root/lib/modules/*/video/nvidia*.ko
        do
                /usr/src/linux/scripts/sign-file \
                    sha512 "$keydir/sign.key" "$keydir/sign.crt" "$module"
        done

        # Make NVIDIA use kernel mode setting and the page attribute table.
        cat << 'EOF' > root/usr/lib/modprobe.d/nvidia-config.conf
options nvidia NVreg_UsePageAttributeTable=1
options nvidia-drm modeset=1
softdep nvidia post: nvidia-uvm
EOF

        # Support an executable VM image for quick testing.
        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu
exec qemu-kvm -nodefaults \
    -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \
    -cpu host -m 8G -vga std -nic user \
    -drive file="${IMAGE:-gpt.img}",format=raw,media=disk \
    -device intel-hda -device hda-output \
    "$@"
EOF
}

function write_system_kernel_config() if opt bootable
then
        cat << 'EOF' >> /etc/kernel/config.d/qemu.config
# TARGET HARDWARE: QEMU
## QEMU default graphics
CONFIG_DRM_BOCHS=m
## QEMU default network
CONFIG_E1000=m
## QEMU default disk
CONFIG_ATA=y
CONFIG_ATA_SFF=y
CONFIG_ATA_BMDMA=y
CONFIG_BLK_DEV_SD=y
CONFIG_ATA_PIIX=y
## QEMU default serial port
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
EOF
        cat >> /etc/kernel/config.d/system.config
fi << 'EOF'
# Show initialization messages.
CONFIG_PRINTK=y
# Support CPU microcode updates.
CONFIG_MICROCODE=y
# Enable bootloader interaction for managing system image updates.
CONFIG_EFI_VARS=y
CONFIG_EFI_BOOTLOADER_CONTROL=y
# Support ext2/ext3/ext4 (which is not included for read-only images).
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_FS_SECURITY=y
CONFIG_EXT4_USE_FOR_EXT2=y
# Support encrypted partitions.
CONFIG_BLK_DEV_DM=y
CONFIG_DM_CRYPT=m
CONFIG_DM_INTEGRITY=m
# Support FUSE.
CONFIG_FUSE_FS=m
# Support running virtual machines in QEMU.
CONFIG_HIGH_RES_TIMERS=y
CONFIG_VIRTUALIZATION=y
CONFIG_KVM=y
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
CONFIG_FB_EFI=y
CONFIG_TTY=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_VGA_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_DRM=y
CONFIG_DRM_FBDEV_EMULATION=y
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
# TARGET HARDWARE: Lenovo Thinkpad P1 (Gen 2)
CONFIG_MNATIVE=y  # Assume the build system is the target.
CONFIG_PCI_MSI=y
CONFIG_PM=y
## Bundle firmware/microcode
CONFIG_EXTRA_FIRMWARE="intel/ibt-20-1-3.ddc intel/ibt-20-1-3.sfi intel-ucode/06-9e-0d iwlwifi-cc-a0-48.ucode regulatory.db regulatory.db.p7s"
## Intel Core i7 9850H
CONFIG_ARCH_RANDOM=y
CONFIG_CPU_SUP_INTEL=y
CONFIG_CRYPTO_SHA256_SSSE3=y
CONFIG_KVM_INTEL=y
CONFIG_MICROCODE_INTEL=y
CONFIG_SCHED_MC=y
CONFIG_SCHED_MC_PRIO=y
## USB 3 support
CONFIG_USB_SUPPORT=y
CONFIG_USB=y
CONFIG_USB_PCI=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_XHCI_PCI=y
## Intel e1000e gigabit Ethernet
CONFIG_NETDEVICES=y
CONFIG_ETHERNET=y
CONFIG_NET_VENDOR_INTEL=y
CONFIG_E1000E=y
## Intel Wi-Fi 6 AX200
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_WLAN=y
CONFIG_WLAN_VENDOR_INTEL=y
CONFIG_IWLMVM=y
CONFIG_IWLWIFI=y
## Bluetooth (built in 5.0 over USB)
CONFIG_BT=y
CONFIG_BT_HCIBTUSB=y
CONFIG_BT_BREDR=y
CONFIG_BT_LE=y
CONFIG_BT_HS=y
## Conexant CX8070 audio
CONFIG_SOUND=y
CONFIG_SND=y
CONFIG_SND_PCI=y
CONFIG_SND_HDA_INTEL=y
CONFIG_SND_HDA_CODEC_CONEXANT=y
## NVIDIA Quadro T2000 (enable modules to build the proprietary driver)
CONFIG_MODULES=y
CONFIG_MODULE_COMPRESS=y
CONFIG_MODULE_COMPRESS_XZ=y
CONFIG_MTRR=y
CONFIG_MTRR_SANITIZER=y
CONFIG_SYSVIPC=y
CONFIG_X86_PAT=y
CONFIG_ZONE_DMA=y
## Input
CONFIG_HID=y
CONFIG_HID_BATTERY_STRENGTH=y
CONFIG_HID_GENERIC=y
CONFIG_INPUT=y
CONFIG_INPUT_EVDEV=y
## Keyboard, touchpad, and trackpoint
CONFIG_INPUT_KEYBOARD=y
CONFIG_INPUT_MOUSE=y
CONFIG_KEYBOARD_ATKBD=y
CONFIG_MOUSE_PS2=y
## Optional USB devices
CONFIG_SND_USB=y
CONFIG_HID_GYRATION=m   # wireless mouse and keyboard
CONFIG_SND_USB_AUDIO=m  # headsets
CONFIG_USB_ACM=m        # fit-PC status LED
CONFIG_USB_HID=m        # mice and keyboards
EOF
