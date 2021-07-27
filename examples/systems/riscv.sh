# SPDX-License-Identifier: GPL-3.0-or-later
# This is an example Gentoo build to try RISC-V on an emulator.  There are some
# things that still need to be implemented in upstream projects, particularly
# around UEFI support.  Secure Boot cannot be enforced with the current setup.

options+=(
        [arch]=riscv64   # Target RISC-V emulators.
        [distro]=gentoo  # Use Gentoo to build this image from source.
        [gpt]=1          # Generate a VM disk image for fast testing.
        [monolithic]=1   # Build all boot-related files into the kernel image.
        [networkd]=1     # Let systemd manage the network configuration.
        [secureboot]=    # This is unused until systemd-boot supports RISC-V.
        [uefi]=1         # This is for hacking purposes only.
        [verity_sig]=1   # Require all verity root hashes to be verified.
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
            apng exif gif imagemagick jbig jpeg jpeg2k png svg tiff webp xpm \
            a52 alsa cdda faad flac libcanberra libsamplerate mp3 ogg opus pulseaudio sndfile sound speex vorbis \
            aacs aom bdplus bluray cdio dav1d dvd ffmpeg libaom mpeg theora vpx x265 \
            brotli bzip2 gzip lz4 lzma lzo snappy xz zlib zstd \
            cryptsetup gcrypt gmp gnutls gpg mpfr nettle \
            curl http2 ipv6 libproxy modemmanager networkmanager wifi wps \
            acl caps cracklib fprint hardened pam policykit seccomp smartcard xattr xcsecurity \
            acpi dri gallium gusb kms libglvnd libkms opengl upower usb uvm vaapi vdpau \
            cairo colord gtk gtk3 gui lcms libdrm pango uxa wnck X xa xcb xft xinerama xkb xorg xrandr xvmc xwidgets \
            aio branding haptic jit lto offensive pcap realtime system-info threads udisks utempter vte \
            dynamic-loading gzip-el hwaccel postproc repart startup-notification toolkit-scroll-bars user-session wide-int \
            -cups -dbusmenu -debug -geolocation -gstreamer -llvm -oss -perl -python -sendmail -tcpd \
            -gtk -gui -opengl -repart -X'"'

        # Build a static RISC-V QEMU in case the host system's QEMU is too old.
        packages_buildroot+=(app-emulation/qemu)
        $cat << 'EOF' >> "$buildroot/etc/portage/package.use/qemu.conf"
app-emulation/qemu -* fdt pin-upstream-blobs python_targets_python3_9 qemu_softmmu_targets_riscv64 qemu_user_targets_riscv64 slirp static static-user
dev-libs/glib static-libs
dev-libs/libffi static-libs
dev-libs/libpcre static-libs
dev-libs/libxml2 static-libs
net-libs/libslirp static-libs
sys-apps/dtc static-libs
sys-apps/util-linux static-libs
sys-libs/zlib static-libs
x11-libs/pixman static-libs
EOF

        # Block GCC 11 since it won't cross-compile (GCC#100017).
        echo ">=cross-${options[host]}/gcc-11" >> "$buildroot/etc/portage/package.mask/gcc.conf"
        echo '>=sys-devel/gcc-11' >> "$portage/package.mask/gcc.conf"

        # Fix the spidermonkey linker since gold does not exist for riscv.
        echo 'EXTRA_ECONF="--enable-linker=bfd"' >> "$portage/env/spidermonkey.conf"
        echo 'dev-lang/spidermonkey spidermonkey.conf' >> "$portage/package.env/spidermonkey.conf"

        # Build RISC-V UEFI GRUB for bootloader testing.
        packages_buildroot+=(sys-boot/grub)
        $curl -L https://lists.gnu.org/archive/mbox/grub-devel/2020-04 > "$output/grub.mbox"
        test x$($sha256sum "$output/grub.mbox" | $sed -n '1s/ .*//p') = \
            x32d142f8af7a0d4c1bf3cb0455e8cb9b4107125a04678da0f471044d90f28137
        $mkdir -p "$buildroot/etc/portage/patches/sys-boot/grub"
        local -i p ; for p in 1 2 3
        do $sed -n "/t:[^:]*RFT $p/,/^2.25/p" "$output/grub.mbox"
        done > "$buildroot/etc/portage/patches/sys-boot/grub/riscv-uefi.patch"
        $rm -f "$output/grub.mbox"
        echo -e 'GRUB_AUTOGEN="1"\nGRUB_AUTORECONF="1"' >> "$buildroot/etc/portage/env/grub.conf"
        echo 'sys-boot/grub grub.conf' >> "$buildroot/etc/portage/package.env/grub.conf"

        # Download sources to build a UEFI firmware image.
        $curl -L https://github.com/riscv/opensbi/archive/v0.9.tar.gz > "$buildroot/root/opensbi.tgz"
        test x$($sha256sum "$buildroot/root/opensbi.tgz" | $sed -n '1s/ .*//p') = \
            x60f995cb3cd03e3cf5e649194d3395d0fe67499fd960a36cf7058a4efde686f0
        $curl -L https://github.com/u-boot/u-boot/archive/v2021.07.tar.gz > "$buildroot/root/u-boot.tgz"
        test x$($sha256sum "$buildroot/root/u-boot.tgz" | $sed -n '1s/ .*//p') = \
            x6cc8e2c9ed8898750c8979e0f75317818c1a7493b21f8ba4154f88888b675b5f

        # Work around the broken baselayout migration code (#796893).
        $mkdir -p "$buildroot/usr/${options[host]}/usr/lib64"

        # Work around the broken glibc paths (#797679).
        $ln -fst "$buildroot/usr/lib64" "../${options[host]}/usr/lib64/lp64d"

        # Work around broken UEFI booting on Linux 5.13.
        echo '>=sys-kernel/gentoo-sources-5.13' >> "$buildroot/etc/portage/package.mask/linux.conf"
}

function customize_buildroot() {
        # Build less useless stuff on the host from bad dependencies.
        echo >> /etc/portage/make.conf 'USE="$USE' \
            -cups -debug -emacs -geolocation -gstreamer -llvm -oss -perl -python -sendmail -tcpd -X'"'

        # Configure the kernel by only enabling this system's settings.
        write_system_kernel_config

        # Work around the broken baselayout migration code (#796893).
        mkdir -p "root/usr/lib64"
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

        # Dump emacs into the image since QEMU is built already anyway.
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
        tar --transform='s,^/*[^/]*,u-boot,' -C /root -xf /root/u-boot.tgz
        cat /root/u-boot/configs/qemu-riscv64_smode_defconfig - << 'EOF' > /root/u-boot/.config
CONFIG_BOOTCOMMAND="fatload virtio 0:1 ${kernel_addr_r} /EFI/BOOT/BOOTRISCV64.EFI;bootefi ${kernel_addr_r}"
CONFIG_BOOTDELAY=0
EOF
        make -C /root/u-boot -j"$(nproc)" olddefconfig CROSS_COMPILE="$host-" V=1
        make -C /root/u-boot -j"$(nproc)" all CROSS_COMPILE="$host-" V=1

        # Build OpenSBI with a U-Boot payload for the firmware image.
        tar --transform='s,^/*[^/]*,opensbi,' -C /root -xf /root/opensbi.tgz
        make -C /root/opensbi -j"$(nproc)" all \
            CROSS_COMPILE="$host-" FW_PAYLOAD_PATH=/root/u-boot/u-boot.bin PLATFORM=generic V=1
        cp -p /root/opensbi/build/platform/generic/firmware/fw_payload.bin opensbi-uboot.bin
        chmod 0644 opensbi-uboot.bin

        # Support an executable VM image for quick testing.
        cp -pt . /usr/bin/qemu-system-riscv64
        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/bash -eu
exec qemu-system-riscv64 -nographic \
    -L "$PWD" -bios opensbi-uboot.bin \
    -machine virt -cpu rv64 -m 4G \
    -drive file="${IMAGE:-gpt.img}",format=raw,id=hd0,media=disk \
    -netdev user,id=net0 \
    -object rng-random,id=rng0 \
    -device virtio-blk-device,drive=hd0 \
    -device virtio-net-device,netdev=net0 \
    -device virtio-rng-device,rng=rng0 \
    "$@"
EOF
}

# Override the UEFI function as a hack to produce a UEFI GRUB image for the
# bootloader until the systemd boot stub exists for RISC-V.
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
mcopy -i esp.img vmlinuz ::/linux_a\
test -s initrd.img && mcopy -i esp.img initrd.img ::/initrd_a\
mcopy -i esp.img grub.cfg ::/grub.cfg')"

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
