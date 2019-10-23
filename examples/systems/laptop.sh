# This is an example Gentoo build for a specific target system, the Lenovo
# Thinkpad P1 (Gen 2).  It only supports exactly that hardware to demonstrate a
# minimal targeted build.  The kernel configuration is built from "allnoconfig"
# so it doesn't include many things that would be taken for granted on other
# distros.  This file is a work in progress; it will eventually have a desktop.

options+=(
        [distro]=gentoo  # Use Gentoo to build this image from source.
        [executable]=1   # Generate a VM image for fast testing.
        [networkd]=1     # Let systemd manage the network configuration.
        [ramdisk]=1      # Bundle the root file system into an initrd.
        [selinux]=1      # Load a targeted SELinux policy in permissive mode.
        [squash]=1       # Use a highly compressed file system to save space.
        [uefi]=1         # Create a UEFI executable that boots into this image.
        [verity]=1       # Prevent the file system from being modified.
)

packages+=(
        # Utilities
        app-editors/emacs
        app-shells/bash
        dev-vcs/git
        sys-apps/findutils
        sys-apps/gawk
        sys-apps/grep
        sys-apps/kbd
        sys-apps/less
        sys-apps/man-pages
        sys-apps/sed
        sys-apps/which
        sys-process/procps
        ## Accounts
        app-admin/sudo
        sys-apps/shadow
        ## Network
        net-firewall/iptables
        net-misc/wget
        net-wireless/wpa_supplicant

        # Graphics
        x11-apps/xrandr
        x11-drivers/nvidia-drivers
        x11-drivers/xf86-input-libinput
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

        # The Git dependency for gettext should be in BDEPEND.
        dev-vcs/git
)

function customize_buildroot() {
        local -r sysroot="$buildroot/usr/${options[arch]}-gentoo-linux-gnu"

        # Assume the build system is the target, and tune compilation for it.
        $sed -i \
            -e '/^COMMON_FLAGS=/s/[" ]*$/ -march=native -ftree-vectorize&/' \
            "$sysroot/etc/portage/make.conf"
        enter /usr/bin/cpuid2cpuflags |
        $sed -n 's/^\([^ :]*\): \(.*\)/\1="\2"/p' >> "$sysroot/etc/portage/make.conf"

        # Enable general system settings.
        echo >> "$sysroot/etc/portage/make.conf" 'USE="$USE' \
            curl emacs gcrypt gdbm git gmp gpg imagemagick libxml2 lzma mpfr ncurses pcre2 readline sqlite udev uuid \
            icu idn libidn2 nls unicode \
            apng gif jpeg jpeg2k png svg webp xpm \
            acl caps cracklib pam seccomp xattr xcsecurity \
            acpi dri kms libglvnd opengl smartcard usb uvm vaapi vdpau wifi \
            cairo gtk3 pulseaudio X xcb xinerama xkb xorg \
            branding cet dynamic-loading ipv6 jit offensive threads wide-int \
            -gallium -llvm -perl -python -sendmail'"'

        # Build less useless stuff on the host from bad dependencies.
        echo >> "$buildroot/etc/portage/make.conf" \
            'USE="$USE' -gallium -llvm -perl -python -sendmail -X'"'
        echo >> "$buildroot/etc/portage/make.conf" 'VIDEO_CARDS=""'

        # Don't build Emacs as a GUI application.
        echo 'app-editors/emacs -X' >> "$sysroot/etc/portage/package.use/emacs.conf"

        # Use the latest NVIDIA drivers.
        echo 'VIDEO_CARDS="nvidia"' >> "$sysroot/etc/portage/make.conf"
        echo x11-drivers/nvidia-drivers >> "$sysroot/etc/portage/package.accept_keywords/nvidia.conf"
        echo 'x11-drivers/nvidia-drivers NVIDIA-r2' >> "$sysroot/etc/portage/package.license/nvidia.conf"
        echo 'x11-drivers/nvidia-drivers -tools' >> "$sysroot/etc/portage/package.use/nvidia.conf"

        # Produce the kernel config by disabling everything, then enabling system settings.
        write_minimal_system_kernel_configuration > "$output/config"
        enter /usr/bin/make -C /usr/src/linux allnoconfig KCONFIG_ALLCONFIG=/wd/config V=1
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
CONFIG_DM_CRYPT=y
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
# TARGET HARDWARE: Lenovo Thinkpad P1 (Gen 2)
## Bundle firmware/microcode for CPU, wifi, bluetooth
CONFIG_EXTRA_FIRMWARE="intel-ucode/06-9e-0d iwlwifi-cc-a0-48.ucode intel/ibt-20-1-3.sfi regulatory.db regulatory.db.p7s"
## Intel Core i7 9850H
CONFIG_ARCH_RANDOM=y
CONFIG_CPU_SUP_INTEL=y
CONFIG_CRYPTO_SHA256_SSSE3=y
CONFIG_KVM_INTEL=y
CONFIG_MICROCODE_INTEL=y
CONFIG_SCHED_MC=y
CONFIG_SCHED_MC_PRIO=y
## NVMe hard drive
CONFIG_BLK_DEV_NVME=y
## Intel Wi-Fi 6 AX200
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_NETDEVICES=y
CONFIG_WLAN=y
CONFIG_WLAN_VENDOR_INTEL=y
CONFIG_IWLMVM=y
CONFIG_IWLWIFI=y
## Nvidia Quadro T2000 (enable modules to build the proprietary driver)
CONFIG_MODULES=y
CONFIG_MODULE_COMPRESS=y
CONFIG_MODULE_COMPRESS_XZ=y
CONFIG_MTRR=y
CONFIG_MTRR_SANITIZER=y
CONFIG_SYSVIPC=y
CONFIG_ZONE_DMA=y
## Input
CONFIG_INPUT=y
CONFIG_INPUT_EVDEV=y
# TARGET HARDWARE: QEMU
## QEMU default graphics
CONFIG_DRM_BOCHS=y
## QEMU default network
CONFIG_NETDEVICES=y
CONFIG_ETHERNET=y
CONFIG_NET_VENDOR_INTEL=y
CONFIG_E1000=y
## QEMU default PS/2 input
CONFIG_INPUT_KEYBOARD=y
CONFIG_INPUT_MOUSE=y
CONFIG_KEYBOARD_ATKBD=y
CONFIG_MOUSE_PS2=y
## QEMU default disk
CONFIG_PCI=y
CONFIG_ATA=y
CONFIG_ATA_BMDMA=y
CONFIG_ATA_SFF=y
CONFIG_BLK_DEV_SD=y
CONFIG_ATA_PIIX=y
EOF
