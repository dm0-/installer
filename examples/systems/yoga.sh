# SPDX-License-Identifier: GPL-3.0-or-later
# This is an example Gentoo build for a specific target system, the Lenovo
# Yoga 2 11" (based on the Intel Pentium N3530 CPU).  It demonstrates
# cross-compiling for an x86_64 system using the x32 ABI.  This currently
# requires using x86_64 for the build system to create the x64 UEFI files.
#
# After writing gpt.img to an SD card or USB drive, it can be selected as the
# UEFI boot device by starting the system using the Novo button.

options+=(
        [distro]=gentoo         # Use Gentoo to build this image from source.
        [arch]=x86_64           # Target Intel Pentium N3530 CPUs.
        [gpt]=1                 # Generate a ready-to-boot full disk image.
        [squash]=1              # Use a compressed file system to save space.
        [uefi]=1                # Create a UEFI executable to boot this image.
        [verity_sig]=1          # Require verifying all verity root hashes.

        # Customize the target triplet and profile for the x32 ABI.
        [host]=x86_64-gentoo-linux-gnux32
        [profile]=default/linux/amd64/17.0/x32
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
)

packages_buildroot+=(
        # The target hardware requires firmware.
        net-wireless/wireless-regdb
        sys-firmware/intel-microcode
)

function initialize_buildroot() {
        local -r portage="$buildroot/usr/${options[host]}/etc/portage"

        # Tune compilation for the Intel Pentium N3530, and use the x32 ABI.
        $sed -i \
            -e '/^COMMON_FLAGS=/s/[" ]*$/ -march=silvermont -ftree-vectorize&/' \
            -e '/^RUSTFLAGS=/s/[" ]*$/ -Ctarget-cpu=silvermont&/' \
            "$portage/make.conf"
        $cat << 'EOF' >> "$portage/make.conf"
ABI_X86="x32"
CPU_FLAGS_X86="mmx mmxext pclmul popcnt rdrand sse sse2 sse3 sse4_1 sse4_2 ssse3"
RUST_TARGET="x86_64-unknown-linux-gnux32"
EOF
        echo >> "$buildroot/etc/portage/env/rust-map.conf" \
            "RUST_CROSS_TARGETS=\"$(archmap_llvm x86_64):x86_64-unknown-linux-gnux32:${options[host]}\""
        echo 'dev-lang/rust rust-map.conf' >> "$buildroot/etc/portage/package.env/rust.conf"

        # Use the i915 video driver for the integrated GPU.
        echo 'VIDEO_CARDS="intel i915"' >> "$portage/make.conf"
        echo 'media-libs/mesa -classic -video_cards_intel' >> "$portage/package.use/mesa.conf"
        packages+=(x11-libs/libva-intel-driver)

        # Use the proprietary Broadcom drivers.
        echo 'USE="$USE broadcom-sta kmod"' >> "$portage/make.conf"
        echo net-wireless/broadcom-sta >> "$portage/package.accept_keywords/broadcom.conf"
        echo 'net-wireless/broadcom-sta Broadcom' >> "$portage/package.license/broadcom.conf"
        echo 'net-wireless/wpa_supplicant -fils -mbo -mesh' >> "$portage/package.use/broadcom.conf"
        packages+=(net-wireless/broadcom-sta)

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
            acpi dri gusb kms libglvnd opengl upower usb uvm vaapi vdpau \
            cairo colord gtk gtk3 gui lcms libdrm pango uxa wnck X xa xcb xft xinerama xkb xorg xrandr xvmc xwidgets \
            aio branding haptic jit lto offensive pcap realtime system-info threads udisks utempter vte \
            dynamic-loading gzip-el hwaccel postproc startup-notification toolkit-scroll-bars wide-int \
            -cups -dbusmenu -debug -geolocation -gstreamer -llvm -oss -perl -python -sendmail \
            -gui -modemmanager -ppp'"'

        # Build a native (amd64) systemd boot stub since there is no x32 UEFI.
        echo 'sys-apps/systemd gnuefi' >> "$buildroot/etc/portage/package.use/systemd.conf"
        echo gnuefi >> "$portage/profile/use.mask/uefi.conf"

        # Enable extra bootstrapping objects for x32.
        echo 'sys-libs/glibc multilib-bootstrap' >> "$portage/package.use/glibc.conf"

        # Fix libvpx.
        $mkdir -p "$portage/patches/media-libs/libvpx"
        $cat << 'EOF' > "$portage/patches/media-libs/libvpx/x32.patch"
--- a/third_party/x86inc/x86inc.asm
+++ b/third_party/x86inc/x86inc.asm
@@ -72,6 +72,8 @@
     %define FORMAT_ELF 1
 %elifidn __OUTPUT_FORMAT__,elf32
     %define FORMAT_ELF 1
+%elifidn __OUTPUT_FORMAT__,elfx32
+    %define FORMAT_ELF 1
 %elifidn __OUTPUT_FORMAT__,elf64
     %define FORMAT_ELF 1
 %elifidn __OUTPUT_FORMAT__,macho
EOF

        # Fix libaom.
        $mkdir -p "$portage/patches/media-libs/libaom"
        $cat - "$portage/patches/media-libs/libvpx/x32.patch" << 'EOF' > "$portage/patches/media-libs/libaom/x32.patch"
--- a/build/cmake/aom_optimization.cmake
+++ b/build/cmake/aom_optimization.cmake
@@ -104,7 +104,7 @@
            OR "${AOM_TARGET_SYSTEM}" STREQUAL "Windows")
       set(objformat "win64")
     else()
-      set(objformat "elf64")
+      set(objformat "elfx32")
     endif()
   elseif("${AOM_TARGET_CPU}" STREQUAL "x86")
     if("${AOM_TARGET_SYSTEM}" STREQUAL "Darwin")
EOF
        echo 'MYCMAKEARGS="-DAOM_TARGET_CPU=x86_64"' >> "$portage/env/libaom.conf"
        echo 'media-libs/libaom libaom.conf' >> "$portage/package.env/libaom.conf"

        # Fix broadcom-sta with Linux 5.18.
        $mkdir -p "$portage/patches/net-wireless/broadcom-sta"
        $curl -L > "$portage/patches/net-wireless/broadcom-sta/5.18.patch" \
            https://raw.githubusercontent.com/archlinux/svntogit-community/33b4bd2b9e30679b03f5d7aa2741911d914dcf94/trunk/012-linux517.patch \
            https://raw.githubusercontent.com/archlinux/svntogit-community/2e1fd240f9ce06f500feeaa3e4a9675e65e6b967/trunk/013-linux518.patch
        [[ $($sha256sum "$portage/patches/net-wireless/broadcom-sta/5.18.patch") == 29501d6eb4399c472e409df504e3ad67d71b01d1d98e31ade129f9a43a7d4fa0\ * ]]
        $sed -i -e 's/if.*4.*15.*/ifdef HAVE_TIMER_SETUP/' "$portage/patches/net-wireless/broadcom-sta/5.18.patch"
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

        echo yoga > root/etc/hostname

        # Drop extra unused paths.
        exclude_paths+=(
                {,usr/lib/debug/}{,usr/}lib64
                usr/lib/firmware
                usr/local
                usr/share/qemu/'*'{aarch,arm,hppa,ppc,riscv,s390,sparc}'*'
        )

        # Sign the out-of-tree kernel modules due to required signatures.
        for module in root/lib/modules/*/net/wireless/wl.ko.zst
        do
                unzstd --rm "$module" ; module=${module%.zst}
                /usr/src/linux/scripts/sign-file \
                    sha512 "$keydir/sign.key" "$keydir/sign.crt" "$module"
        done

        # Support an executable VM image for quick testing.
        cat << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu
exec qemu-kvm -nodefaults \
    -M q35 -cpu host -smp 4,cores=4 -m 4G -vga std -nic user \
    -drive file=/usr/share/edk2/ovmf/OVMF_CODE.fd,format=raw,if=pflash,read-only=on \
    -drive file="${IMAGE:-gpt.img}",format=raw,media=disk,snapshot=on \
    -device intel-hda -device hda-output \
    "$@"
EOF
}

# Override kernel builds to use the native (assumed amd64) compiler, not x32.
eval "$(declare -f install_packages save_boot_files | $sed 's/ CROSS_COMPILE=[^ ]* / /')"

# Override the UEFI function to skip Gentoo and use the generic native version.
declare -f produce_uefi_exe.orig &>/dev/null &&
eval "$(declare -f produce_uefi_exe.orig | $sed 's/\(produce_uefi_exe\).orig/\1/')" &&
unset produce_uefi_exe.orig ||
eval "$(declare -f produce_uefi_exe | $sed 's/produce_uefi_exe/&.orig/')"

function write_system_kernel_config() if opt bootable
then
        cat << 'EOF' >> /etc/kernel/config.d/qemu.config.disabled
# TARGET HARDWARE: QEMU
## QEMU default graphics
CONFIG_DRM_BOCHS=m
## QEMU default network
CONFIG_ETHERNET=y
CONFIG_NET_VENDOR_INTEL=y
CONFIG_E1000=m
## QEMU default disk
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
CONFIG_FB=y
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
# TARGET HARDWARE: Lenovo Yoga 2 11"
CONFIG_MTRR=y
CONFIG_PCI=y
CONFIG_PCI_MSI=y
CONFIG_PM=y
CONFIG_X86_PAT=y
## Bundle firmware/microcode
CONFIG_EXTRA_FIRMWARE="intel-ucode/06-37-08 regulatory.db regulatory.db.p7s"
## Intel Pentium N3530
CONFIG_MSILVERMONT=y
CONFIG_ARCH_RANDOM=y
CONFIG_CPU_SUP_INTEL=y
CONFIG_CRYPTO_SHA256_SSSE3=y
CONFIG_KVM_INTEL=y
CONFIG_MICROCODE_INTEL=y
CONFIG_NR_CPUS=4
CONFIG_SCHED_MC=y
CONFIG_SCHED_MC_PRIO=y
## Integrated GPU
CONFIG_DRM_I915=y
## Conexant CX20756 audio
CONFIG_SOUND=y
CONFIG_SND=y
CONFIG_SND_PCI=y
CONFIG_SND_HDA_INTEL=y
CONFIG_SND_HDA_CODEC_CONEXANT=y
## AHCI SATA disk
CONFIG_ATA=y
CONFIG_SATA_AHCI=y
## USB 3 support
CONFIG_USB_SUPPORT=y
CONFIG_USB=y
CONFIG_USB_PCI=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_XHCI_PCI=y
## Broadcom wireless BCM43142 (enable modules to build the proprietary driver)
CONFIG_MODULES=y
CONFIG_NETDEVICES=y
CONFIG_WIRELESS=y
CONFIG_CFG80211=y
CONFIG_PACKET=y  # Required by NetworkManager-wifi
## Input
CONFIG_HID=y
CONFIG_HID_BATTERY_STRENGTH=y
CONFIG_HID_GENERIC=y
CONFIG_INPUT=y
CONFIG_INPUT_EVDEV=y
## Keyboard, touchpad, and touchscreen
CONFIG_INPUT_KEYBOARD=y
CONFIG_INPUT_MOUSE=y
CONFIG_KEYBOARD_ATKBD=y
CONFIG_MOUSE_PS2=y
## Webcam
CONFIG_MEDIA_SUPPORT=y
CONFIG_MEDIA_CAMERA_SUPPORT=y
CONFIG_MEDIA_USB_SUPPORT=y
CONFIG_USB_VIDEO_CLASS=y
CONFIG_VIDEO_DEV=y
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
