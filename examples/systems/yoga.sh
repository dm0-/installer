# SPDX-License-Identifier: GPL-3.0-or-later
# This is an example Gentoo build for a specific target system, the Lenovo
# Yoga 2 11" (based on the Intel Pentium N3530 CPU).  It demonstrates
# cross-compiling for an x86_64 system using the x32 ABI.  This currently
# requires using x86_64 for the build system to create the x64 UEFI files.
#
# After writing gpt.img to an SD card or USB drive, it can be selected as the
# UEFI boot device by starting the system using the Novo button.

options+=(
        [arch]=x86_64    # Target Intel Pentium N3530 CPUs.
        [distro]=gentoo  # Use Gentoo to build this image from source.
        [gpt]=1          # Generate a VM disk image for fast testing.
        [networkd]=1     # Let systemd manage the network configuration.
        [squash]=1       # Use a highly compressed file system to save space.
        [uefi]=1         # Create a UEFI executable that boots into this image.
        [verity_sig]=1   # Require all verity root hashes to be verified.

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
        app-shells/bash
        dev-util/strace
        dev-vcs/git
        sys-apps/coreutils
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
            "$portage/make.conf"
        $cat << 'EOF' >> "$portage/make.conf"
ABI_X86="x32"
CPU_FLAGS_X86="mmx mmxext pclmul popcnt rdrand sse sse2 sse3 sse4_1 sse4_2 ssse3"
RUST_TARGET="x86_64-unknown-linux-gnux32"
RUSTFLAGS="-C target-cpu=silvermont"
EOF
        echo >> "$buildroot/etc/portage/env/rust-map.conf" \
            "RUST_CROSS_TARGETS=\"$(archmap_llvm x86_64):x86_64-unknown-linux-gnux32:${options[host]}\""
        echo 'dev-lang/rust rust-map.conf' >> "$buildroot/etc/portage/package.env/rust.conf"

        # Use the i915 video driver for the integrated GPU.
        echo 'VIDEO_CARDS="intel i915"' >> "$portage/make.conf"
        echo 'media-libs/mesa -classic -video_cards_intel' >> "$portage/package.use/mesa.conf"

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
            curl http2 ipv6 libproxy modemmanager networkmanager wifi wps \
            acl caps cracklib fprint hardened pam policykit seccomp smartcard xattr xcsecurity \
            acpi dri gallium gusb kms libglvnd libkms opengl upower usb uvm vaapi vdpau \
            cairo colord gtk gtk3 gui lcms libdrm pango uxa wnck X xa xcb xft xinerama xkb xorg xrandr xvmc xwidgets \
            aio branding haptic jit lto offensive pcap system-info threads udisks utempter vte \
            dynamic-loading gzip-el hwaccel postproc repart startup-notification toolkit-scroll-bars user-session wide-int \
            -cups -dbusmenu -debug -geolocation -gstreamer -llvm -oss -perl -python -sendmail -tcpd \
            -gui -networkmanager -policykit -repart -udisks -wifi'"'

        # Build a native (amd64) systemd boot stub since there is no x32 UEFI.
        echo 'sys-apps/systemd gnuefi' >> "$buildroot/etc/portage/package.use/systemd.conf"

        # Block PolicyKit since Mozilla stuff won't build for x32.
        echo xfce-extra/thunar-volman-9999 >> "$portage/profile/package.provided"

        # Enable extra bootstrapping objects for x32.
        echo 'sys-libs/glibc multilib-bootstrap' >> "$portage/package.use/glibc.conf"

        # Fix librsvg.
        $mkdir -p "$portage/patches/gnome-base/librsvg"
        $curl -L https://github.com/heycam/thin-slice/pull/1/commits/5db6f6cc8322e7b0211c51d61ace9552d8d820ee.patch > "$portage/patches/gnome-base/librsvg/x32.patch"
        test x$($sha256sum "$portage/patches/gnome-base/librsvg/x32.patch" | $sed -n '1s/ .*//p') = \
            x7f02638d7b895b7ef653f2eb2c8c7e174ff75fca4e26389c7b629855493da0ea
        $sed -i -e 's,^[+-][+-][+-] [ab]/,&vendor/thin-slice/,' "$portage/patches/gnome-base/librsvg/x32.patch"
        $cat << 'EOF' >> "$portage/patches/gnome-base/librsvg/x32.patch"
--- a/vendor/thin-slice/.cargo-checksum.json
+++ b/vendor/thin-slice/.cargo-checksum.json
@@ -1 +1 @@
-{"files":{"Cargo.toml":"bc648e7794ea9bf0b7b520a0ba079ef65226158dc6ece1e617beadc52456e1b7","README.md":"4a83c0adbfdd3ae8047fe4fd26536d27b4e8db813f9926ee8ab09b784294e50f","src/lib.rs":"5b1f2bfc9edfc6036a8880cde88f862931eec5036e6cf63690f82921053b29fe"},"package":"8eaa81235c7058867fa8c0e7314f33dcce9c215f535d1913822a2b3f5e289f3c"}
\ No newline at end of file
+{"files":{},"package":"8eaa81235c7058867fa8c0e7314f33dcce9c215f535d1913822a2b3f5e289f3c"}
EOF

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

        # Fix qemu.
        $mkdir -p "$portage/patches/app-emulation/qemu"
        $cat << 'EOF' >> "$portage/patches/app-emulation/qemu/x32.patch"
--- a/configure
+++ b/configure
@@ -6362,7 +6362,7 @@
         i386)
             echo "cpu_family = 'x86'" >> $cross
             ;;
-        x86_64)
+        x86_64|x32)
             echo "cpu_family = 'x86_64'" >> $cross
             ;;
         ppc64le)
EOF
}

function customize_buildroot() {
        # Build less useless stuff on the host from bad dependencies.
        echo >> /etc/portage/make.conf 'USE="$USE' \
            -cups -debug -emacs -geolocation -gstreamer -llvm -oss -perl -python -sendmail -tcpd -X'"'

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

        # Start the wireless interface if it is configured.
        mkdir -p root/usr/lib/systemd/system/network.target.wants
        ln -fns ../wpa_supplicant-nl80211@.service \
            root/usr/lib/systemd/system/network.target.wants/wpa_supplicant-nl80211@wlp1s0.service

        # Sign the out-of-tree kernel modules due to required signatures.
        for module in root/lib/modules/*/net/wireless/wl.ko
        do
                /usr/src/linux/scripts/sign-file \
                    sha512 "$keydir/sign.key" "$keydir/sign.crt" "$module"
        done

        # Support an executable VM image for quick testing.
        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu
exec qemu-kvm -nodefaults \
    -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \
    -cpu host -smp 1,cores=4 -m 4G -vga std -nic user \
    -drive file="${IMAGE:-gpt.img}",format=raw,media=disk \
    -device intel-hda -device hda-output \
    "$@"
EOF
}

# Override using a cross-compiled UEFI stub in Gentoo.  There is no x32 ABI for
# the UEFI stuff, so fall back to using the native (assumed amd64) version.
eval "$(declare -f install_packages save_boot_files | $sed 's/ CROSS_COMPILE=[^ ]* / /')"
eval "$(declare -f save_boot_files | $sed /systemd/d)"
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
# TARGET HARDWARE: Lenovo Yoga 2 11"
CONFIG_PCI=y
CONFIG_PCI_MSI=y
CONFIG_PM=y
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
CONFIG_MODULE_COMPRESS_XZ=y
CONFIG_NETDEVICES=y
CONFIG_WIRELESS=y
CONFIG_CFG80211=y
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
CONFIG_VIDEO_V4L2=y
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
