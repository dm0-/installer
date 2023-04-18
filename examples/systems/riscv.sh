# SPDX-License-Identifier: GPL-3.0-or-later
# This is an example Gentoo build to try RISC-V on an emulator.  There are some
# things that still need to be implemented in upstream projects, particularly
# around UEFI support.  Secure Boot cannot be enforced with the current setup.

options+=(
        [distro]=gentoo         # Use Gentoo to build this image from source.
        [arch]=riscv64          # Target generic emulated RISC-V CPUs.
        [gpt]=1                 # Generate a ready-to-boot full disk image.
        [loadpin]=1             # Only load kernel files from the root FS.
        [monolithic]=1          # Build all boot-related files into the kernel.
        [networkd]=1            # Let systemd manage the network configuration.
        [secureboot]=           # Wait until systemd-boot supports RISC-V.
        [uefi]=1                # Create a UEFI executable to boot this image.
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
        ## Network
        net-firewall/iptables
        net-misc/openssh
        net-misc/wget
        sys-apps/iproute2

        # Disks
        net-fs/sshfs
        sys-fs/cryptsetup
        sys-fs/e2fsprogs
)

function initialize_buildroot() {
        local -r portage="$buildroot/usr/${options[host]}/etc/portage"

        # Packages just aren't keyworded enough, so accept anything stabilized.
        echo 'ACCEPT_KEYWORDS="*"' >> "$portage/make.conf"

        # Enable general system settings.
        echo >> "$portage/make.conf" 'USE="$USE' \
            berkdb dbus elfutils emacs gdbm git glib json libnotify libxml2 magic ncurses pcre2 readline sqlite udev uuid xml \
            bidi fontconfig fribidi harfbuzz icu idn libidn2 nls truetype unicode \
            apng bmp exif gif imagemagick jbig jpeg jpeg2k png svg tiff webp xcf xpm \
            a52 alsa cdda faad flac libcanberra libsamplerate mp3 ogg opus pulseaudio sndfile sound speex vorbis \
            aacs aom bdplus bluray cdio dav1d dvd ffmpeg libaom mpeg theora vpx x265 \
            brotli bzip2 gzip lz4 lzma lzo snappy xz zlib zstd \
            cryptsetup fido2 gcrypt gmp gnutls gpg mpfr nettle \
            curl http2 ipv6 libproxy mbim modemmanager networkmanager wifi wps \
            acl caps cracklib fprint hardened pam policykit seccomp smartcard xattr xcsecurity \
            acpi dri gusb kms libglvnd opengl upower usb uvm vaapi vdpau \
            cairo colord drm gdk-pixbuf gtk gtk3 gui lcms libdrm pango uxa wnck X xa xcb xft xinerama xkb xorg xrandr xvmc xwidgets \
            aio branding haptic jit lto offensive pcap realtime system-info threads udisks utempter vte \
            dynamic-loading extra gzip-el hwaccel postproc startup-notification toolkit-scroll-bars tray wallpapers wide-int \
            -cups -dbusmenu -debug -geolocation -gstreamer -llvm -oss -perl -python -sendmail \
            -gtk -gui -modemmanager -opengl -X'"'

        # Build a static QEMU user binary for the target CPU.
        packages_buildroot+=(app-emulation/qemu)
        $cat << 'EOF' >> "$buildroot/etc/portage/package.use/qemu.conf"
app-emulation/qemu qemu_user_targets_riscv64 static-user
dev-libs/glib static-libs
dev-libs/libpcre2 static-libs
sys-apps/attr static-libs
sys-libs/zlib static-libs
EOF

        # Build RISC-V UEFI GRUB for bootloader testing.
        packages_buildroot+=(sys-boot/grub)
        $curl -L https://lists.gnu.org/archive/mbox/grub-devel/2020-04 > "$output/grub.mbox"
        [[ $($sha256sum "$output/grub.mbox") == 32d142f8af7a0d4c1bf3cb0455e8cb9b4107125a04678da0f471044d90f28137\ * ]]
        $mkdir -p "$buildroot/etc/portage/patches/sys-boot/grub"
        local -i p ; for p in 1 2 3
        do $sed -n "/t:[^:]*RFT $p/,/^2.25/p" "$output/grub.mbox"
        done > "$buildroot/etc/portage/patches/sys-boot/grub/riscv-uefi.patch"
        $rm -f "$output/grub.mbox"
        echo -e 'GRUB_AUTOGEN="1"\nGRUB_AUTORECONF="1"' >> "$buildroot/etc/portage/env/grub.conf"
        echo 'sys-boot/grub grub.conf' >> "$buildroot/etc/portage/package.env/grub.conf"
        $cat << 'EOF' > "$buildroot/etc/portage/patches/sys-boot/grub/riscv-march.patch"
--- a/configure.ac
+++ b/configure.ac
@@ -868,9 +868,9 @@
 		         [grub_cv_target_cc_soft_float="-march=rv32imac -mabi=ilp32"], [])
     fi
     if test "x$target_cpu" = xriscv64; then
-       CFLAGS="$TARGET_CFLAGS -march=rv64imac -mabi=lp64 -Werror"
+       CFLAGS="$TARGET_CFLAGS -march=rv64imac_zicsr_zifencei -mabi=lp64 -Werror"
        AC_COMPILE_IFELSE([AC_LANG_PROGRAM([[]], [[]])],
-		         [grub_cv_target_cc_soft_float="-march=rv64imac -mabi=lp64"], [])
+		         [grub_cv_target_cc_soft_float="-march=rv64imac_zicsr_zifencei -mabi=lp64"], [])
     fi
     if test "x$target_cpu" = xia64; then
        CFLAGS="$TARGET_CFLAGS -mno-inline-float-divide -mno-inline-sqrt -Werror"
EOF

        # Download sources to build a UEFI firmware image.
        $curl -L https://github.com/riscv-software-src/opensbi/archive/v1.2.tar.gz > "$buildroot/root/opensbi.tgz"
        [[ $($sha256sum "$buildroot/root/opensbi.tgz") == 8fcbce598a73acc2c7f7d5607d46b9d5107d3ecbede8f68f42631dcfc25ef2b2\ * ]]
        $curl -L https://github.com/u-boot/u-boot/archive/v2023.04.tar.gz > "$buildroot/root/u-boot.tgz"
        [[ $($sha256sum "$buildroot/root/u-boot.tgz") == 98ccc5ea7e0f708b7e66a0060ecf1f7f9914d8b31d9d7ad2552027bd0aa848f2\ * ]]
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

        echo riscv > root/etc/hostname

        # Drop extra unused paths.
        exclude_paths+=(
                usr/lib/firmware
                usr/local
        )

        # Dump Emacs into the image with QEMU to skip doing this on boot.
        local -r host=${options[host]}
        local -r gccdir=/$(cd "/usr/$host" ; compgen -G "usr/lib/gcc/$host/*")
        ln -ft "/usr/$host/tmp" /usr/bin/qemu-riscv64
        chroot "/usr/$host" \
            /tmp/qemu-riscv64 -cpu rv64 -E "LD_LIBRARY_PATH=$gccdir" \
            /usr/bin/emacs --batch --eval='(dump-emacs-portable "/tmp/emacs.pdmp")' --quick
        rm -f root/usr/libexec/emacs/*/*/emacs.pdmp \
            root/usr/lib/systemd/system{,/multi-user.target.wants}/emacs-pdmp.service
        cp -pt root/usr/libexec/emacs/*/"$host" "/usr/$host/tmp/emacs.pdmp"

        # Build U-Boot to provide UEFI.
        tar --transform='s,^/*u[^/]*,u-boot,' -C /root -xf /root/u-boot.tgz
        cat /root/u-boot/configs/qemu-riscv64_smode_defconfig - << 'EOF' > /root/u-boot/.config
CONFIG_BOOTDELAY=0
EOF
        make -C /root/u-boot -j"$(nproc)" olddefconfig CROSS_COMPILE="$host-" V=1
        make -C /root/u-boot -j"$(nproc)" all CROSS_COMPILE="$host-" V=1

        # Build OpenSBI with a U-Boot payload for the firmware image.
        tar --transform='s,^/*o[^/]*,opensbi,' -C /root -xf /root/opensbi.tgz
        make -C /root/opensbi -j"$(nproc)" all \
            CROSS_COMPILE="$host-" FW_PAYLOAD_PATH=/root/u-boot/u-boot.bin PLATFORM=generic V=1
        cp -p /root/opensbi/build/platform/generic/firmware/fw_payload.bin opensbi-uboot.bin
        chmod 0644 opensbi-uboot.bin

        # Support an executable VM image for quick testing.
        cat << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu
exec qemu-system-riscv64 -nodefaults -nographic \
    -L "$PWD" -bios opensbi-uboot.bin \
    -machine virt -cpu rv64 -m 4G -serial stdio \
    -drive file="${IMAGE:-gpt.img}",format=raw,id=hd0,media=disk,snapshot=on \
    -netdev user,id=net0 \
    -object rng-random,id=rng0 \
    -device virtio-blk-device,drive=hd0 \
    -device virtio-net-device,netdev=net0 \
    -device virtio-rng-device,rng=rng0 \
    "$@"
EOF
}

# Override the UEFI function as a hack to produce a UEFI GRUB image for the
# bootloader until the systemd boot stub is working for RISC-V.
function produce_uefi_exe() if opt uefi
then
        grub-mkimage \
            --compression=none \
            --format=riscv64-efi \
            --output=BOOTRISCV64.EFI \
            --prefix='(hd0,gpt1)/' \
            fat halt linux loadenv minicmd normal part_gpt reboot test
        cat << EOF > grub.cfg
set default=boot-a
set timeout=3
menuentry 'Boot A' --id boot-a {
        linux /linux_a $(<kernel_args.txt)
        if test -s /initrd_a ; then initrd /initrd_a ; fi
}
menuentry 'U-Boot' --id uboot {
        exit
}
menuentry 'Reboot' --id reboot {
        reboot
}
menuentry 'Power Off' --id poweroff {
        halt
}
EOF
fi

# Override image partitioning to additionally stuff GRUB into the ESP.
declare -f verify_distro &>/dev/null &&
eval "$(declare -f partition | $sed '/^ *mcopy/a\
test -s initrd.img && mcopy -i $esp_image initrd.img ::/initrd_a\
mcopy -i $esp_image vmlinuz ::/linux_a\
mcopy -i $esp_image grub.cfg ::/grub.cfg')"

function write_system_kernel_config() if opt bootable
then cat >> /etc/kernel/config.d/system.config
fi << 'EOF'
# Show initialization messages.
CONFIG_PRINTK=y
## Output early printk messages to the console.
CONFIG_RISCV_SBI_V01=y
CONFIG_HVC_RISCV_SBI=y
CONFIG_SERIAL_EARLYCON_RISCV_SBI=y
# Support ext2/ext3/ext4 (which is not included for read-only images).
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_FS_SECURITY=y
CONFIG_EXT4_USE_FOR_EXT2=y
# Support encrypted partitions.
CONFIG_MD=y
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
# TARGET HARDWARE: QEMU (virtio)
CONFIG_FPU=y
CONFIG_SOC_VIRT=y
CONFIG_VIRTIO_MENU=y
CONFIG_VIRTIO_MMIO=y
## QEMU virtio network
CONFIG_NETDEVICES=y
CONFIG_NET_CORE=y
CONFIG_VIRTIO_NET=y
## QEMU virtio disk
CONFIG_VIRTIO_BLK=y
## QEMU virtio console
CONFIG_TTY=y
CONFIG_VIRTIO_CONSOLE=y
## QEMU virtio RNG
CONFIG_HW_RANDOM=y
CONFIG_HW_RANDOM_VIRTIO=y
EOF
