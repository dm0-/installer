# This is an example Gentoo build for a specific target system, the Lenovo
# Thinkpad P1 (Gen 2).  It only supports exactly that hardware to demonstrate a
# minimal targeted build.  The kernel configuration is built from "allnoconfig"
# so it doesn't include many things that would be taken for granted on other
# distros.  This file is a work in progress; it will eventually have a desktop.

options+=(
        [distro]=gentoo  # Use Gentoo to build this image from source.
        [executable]=1   # Generate a VM image for fast testing.
        [networkd]=1     # Let systemd manage the network configuration.
        [nvme]=1         # Support root on an NVMe disk.
        [selinux]=1      # Load a targeted SELinux policy in permissive mode.
        [squash]=1       # Use a highly compressed file system to save space.
        [uefi]=1         # Create a UEFI executable that boots into this image.
        [verity]=1       # Prevent the file system from being modified.
)

packages+=(
        # Utilities
        app-arch/tar
        app-arch/unzip
        app-shells/bash
        dev-util/strace
        dev-vcs/git
        sys-apps/file
        sys-apps/findutils
        sys-apps/gawk
        sys-apps/grep
        sys-apps/kbd
        sys-apps/less
        sys-apps/man-pages
        sys-apps/sed
        sys-apps/which
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

        # Graphics
        x11-apps/xrandr
        x11-base/xorg-server
        x11-terms/xterm
        x11-wm/twm
)

packages_buildroot+=(
        # Automatically generate the supported instruction set flags.
        app-portage/cpuid2cpuflags

        # The target hardware requires firmware.
        net-wireless/wireless-regdb
        sys-firmware/intel-microcode
        sys-kernel/linux-firmware
)

function customize_buildroot() {
        local -r portage="$buildroot/usr/${options[host]}/etc/portage"

        # Assume the build system is the target, and tune compilation for it.
        $sed -i \
            -e '/^COMMON_FLAGS=/s/[" ]*$/ -march=native -ftree-vectorize -flto=jobserver&/' \
            "$portage/make.conf"
        enter /usr/bin/cpuid2cpuflags |
        $sed -n 's/^\([^ :]*\): \(.*\)/\1="\2"/p' >> "$portage/make.conf"
        echo 'USE="$USE cet"' >> "$portage/make.conf"

        # Use the latest NVIDIA drivers.
        echo -e 'USE="$USE kmod"\nVIDEO_CARDS="nvidia"' >> "$portage/make.conf"
        echo x11-drivers/nvidia-drivers >> "$portage/package.accept_keywords/nvidia.conf"
        echo 'x11-drivers/nvidia-drivers NVIDIA-r2' >> "$portage/package.license/nvidia.conf"
        echo 'x11-drivers/nvidia-drivers -tools' >> "$portage/package.use/nvidia.conf"

        # Enable general system settings.
        echo >> "$portage/make.conf" 'USE="$USE' twm \
            curl gcrypt gdbm git gmp gnutls gpg libxml2 mpfr nettle ncurses pcre2 readline sqlite udev uuid \
            icu idn libidn2 nls unicode \
            apng gif imagemagick jbig jpeg jpeg2k png svg webp xpm \
            bzip2 gzip lz4 lzma lzo xz zlib zstd \
            acl caps cracklib fprint pam seccomp smartcard xattr xcsecurity \
            acpi dri kms libglvnd libkms opengl usb uvm vaapi vdpau wifi wps \
            cairo gtk3 pango plymouth pulseaudio X xcb xinerama xkb xorg \
            branding ipv6 jit lto offensive threads \
            dynamic-loading hwaccel postproc secure-delete wide-int \
            -cups -debug -emacs -fortran -gallium -gtk -gtk2 -introspection -llvm -perl -python -sendmail -vala'"'

        # Build less useless stuff on the host from bad dependencies.
        echo >> "$buildroot/etc/portage/make.conf" 'USE="$USE' \
            -cups -debug -emacs -fortran -gallium -gtk -gtk2 -introspection -llvm -perl -python -sendmail -vala -X'"'

        # Install Emacs as a terminal application.
        packages+=(app-editors/emacs)
        echo 'USE="$USE emacs"' >> "$portage/make.conf"
        echo 'app-editors/emacs -X' >> "$portage/package.use/emacs.conf"

        # Configure the kernel by only enabling this system's settings.
        write_minimal_system_kernel_configuration > "$output/config"
        enter /usr/bin/make -C /usr/src/linux allnoconfig ARCH=x86 \
            CROSS_COMPILE="${options[host]}-" KCONFIG_ALLCONFIG=/wd/config V=1
}

function customize() {
        double_display_scale
        store_home_on_var +root

        echo laptop > root/etc/hostname

        # Drop some building and debugging paths.
        exclude_paths+=(
                usr/include
                usr/lib/.build-id
                usr/lib/debug
                usr/lib/firmware
                usr/libexec/gcc
                usr/local
                usr/share/gcc-data
                usr/src
        )

        # Support an executable VM image for quick testing.
        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu
exec qemu-kvm -nodefaults \
    -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \
    -cpu host -m 8G -vga std -nic user \
    -drive file="${IMAGE:-disk.exe}",format=raw,media=disk \
    "$@"
EOF

        # Make NVIDIA use kernel mode setting and the page attribute table.
        cat << 'EOF' > root/usr/lib/modprobe.d/nvidia.conf
options nvidia NVreg_UsePageAttributeTable=1
options nvidia-drm modeset=1
EOF

        # Sign the out-of-tree kernel modules due to required signatures.
        ! opt sb_key ||
        for module in root/lib/modules/*/video/nvidia*.ko
        do
                /usr/src/linux/scripts/sign-file \
                    sha512 "$keydir/sign.key" "$keydir/sign.crt" "$module"
        done
}

function write_minimal_system_kernel_configuration() { $cat "$output/config.base" - << 'EOF' ; }
# Show initialization messages.
CONFIG_PRINTK=y
# Support CPU microcode updates.
CONFIG_MICROCODE=y
# Enable bootloader interaction for managing system image updates.
CONFIG_EFI_VARS=y
CONFIG_EFI_BOOTLOADER_CONTROL=y
# Support ext2/ext3/ext4 (which is not included otherwise when using squashfs).
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_FS_SECURITY=y
CONFIG_EXT4_USE_FOR_EXT2=y
# Support encrypted partitions.
CONFIG_DM_CRYPT=m
# Support running virtual machines in QEMU.
CONFIG_HIGH_RES_TIMERS=y
CONFIG_VIRTUALIZATION=y
CONFIG_KVM=y
# Support running containers in nspawn.
CONFIG_PID_NS=y
CONFIG_USER_NS=y
CONFIG_UTS_NS=y
# Provide a fancy framebuffer console.
CONFIG_FB=y
CONFIG_FB_EFI=y
CONFIG_TTY=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_VGA_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_DRM=y
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
CONFIG_BPF_JIT=y
CONFIG_BPF_SYSCALL=y
CONFIG_CGROUP_BPF=y
CONFIG_COREDUMP=y
CONFIG_MAGIC_SYSRQ=y
CONFIG_NET_SCHED=y
CONFIG_NET_SCH_DEFAULT=y
CONFIG_NET_SCH_FQ_CODEL=y
# TARGET HARDWARE: Lenovo Thinkpad P1 (Gen 2)
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
## Intel HDA sound
CONFIG_SOUND=y
CONFIG_SND=y
CONFIG_SND_PCI=y
CONFIG_SND_HDA_INTEL=y
## NVIDIA Quadro T2000 (enable modules to build the proprietary driver)
CONFIG_MODULES=y
CONFIG_MODULE_COMPRESS=y
CONFIG_MODULE_COMPRESS_XZ=y
CONFIG_MTRR=y
CONFIG_MTRR_SANITIZER=y
CONFIG_SYSVIPC=y
CONFIG_ZONE_DMA=y
## Keyboard, touchpad, and trackpoint
CONFIG_INPUT_KEYBOARD=y
CONFIG_INPUT_MOUSE=y
CONFIG_KEYBOARD_ATKBD=y
CONFIG_MOUSE_PS2=y
## Input
CONFIG_HID=y
CONFIG_HID_BATTERY_STRENGTH=y
CONFIG_HID_GENERIC=y
CONFIG_INPUT=y
CONFIG_INPUT_EVDEV=y
## Optional USB devices
CONFIG_HID_GYRATION=m  # wireless mouse and keyboard
CONFIG_USB_ACM=m       # fit-PC status LED
CONFIG_USB_HID=m       # mice and keyboards
# TARGET HARDWARE: QEMU
## QEMU default graphics
CONFIG_DRM_BOCHS=m
## QEMU default network
CONFIG_E1000=m
## QEMU default disk
CONFIG_ATA=y
CONFIG_ATA_BMDMA=y
CONFIG_ATA_SFF=y
CONFIG_BLK_DEV_SD=y
CONFIG_ATA_PIIX=y
EOF
