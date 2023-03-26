# SPDX-License-Identifier: GPL-3.0-or-later
# This is a standalone Gentoo workstation image that aims to demonstrate an
# alternative to the Fedora workstation example.  It should be approximately
# equivalent so that they are interchangeable (in terms of applications; i.e.
# Firefox, VLC, Emacs, QEMU, etc. are available).  The main difference is this
# build uses Xfce instead of GNOME for the desktop environment.
#
# Since this is Gentoo, it shows off some pointless build optimizations by
# tuning binaries for the CPU detected on the build system.  To disable this
# and build a generic image, delete the two sections of code containing the
# words "native" and "cpuid2cpuflags".
#
# The proprietary NVIDIA drivers are optionally installed here.  A numeric
# option value selects the driver branch version, and a non-numeric value
# defaults to the latest.

options+=(
        [distro]=gentoo         # Use Gentoo to build this image from source.
        [gpt]=1                 # Generate a ready-to-boot full disk image.
        [loadpin]=1             # Only load kernel files from the root FS.
        [rootmod]=nvme          # Support root on an NVMe disk.
        [selinux]=targeted      # Load this SELinux policy in permissive mode.
        [squash]=1              # Use a compressed file system to save space.
        [uefi]=1                # Create a UEFI executable to boot this image.
        [verity_sig]=1          # Require verifying all verity root hashes.
)

packages+=(
        sys-kernel/gentoo-kernel sys-kernel/linux-firmware

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

        # Browser
        www-client/firefox
)

# Support generating native instruction set flags for supported CPUs.
[[ $DEFAULT_ARCH =~ [3-6x]86|aarch|arm|powerpc ]] && packages_buildroot+=(
        app-portage/cpuid2cpuflags
)

# Install early microcode updates for x86 CPUs.
[[ ${options[arch]:-$DEFAULT_ARCH} == *[3-6x]86* ]] && packages_buildroot+=(
        sys-firmware/intel-microcode
        sys-kernel/linux-firmware
)

function initialize_buildroot() {
        local -r portage="$buildroot/usr/${options[host]}/etc/portage"

        # Assume the build system is the target, and tune compilation for it.
        $sed -i \
            -e '/^COMMON_FLAGS=/s/[" ]*$/ -march=native&/' \
            -e '/^RUSTFLAGS=/s/[" ]*$/ -Ctarget-cpu=native&/' \
            "$portage/make.conf"
        $sed -n '/^vendor_id.*GenuineIntel$/q0;$q1' /proc/cpuinfo && echo CONFIG_MNATIVE_INTEL=y >> "$buildroot/etc/kernel/config.d/native.config"
        $sed -n '/^vendor_id.*AuthenticAMD$/q0;$q1' /proc/cpuinfo && echo CONFIG_MNATIVE_AMD=y >> "$buildroot/etc/kernel/config.d/native.config"

        # Use the latest NVIDIA drivers when requested.
        echo "USE=\"\$USE dist-kernel kmod${options[nvidia]:+ cuda nvenc}\"" >> "$portage/make.conf"
        echo -e 'media-libs/nv-codec-headers\nx11-drivers/nvidia-drivers' >> "$portage/package.accept_keywords/nvidia.conf"
        echo 'x11-drivers/nvidia-drivers NVIDIA-r2' >> "$portage/package.license/nvidia.conf"
        echo 'x11-drivers/nvidia-drivers -tools' >> "$portage/package.use/nvidia.conf"
        [[ -z ${options[nvidia]-} || ${options[nvidia]} == *[!0-9]* ]] ||
        echo ">=x11-drivers/nvidia-drivers-$((options[nvidia]+1))" >> "$portage/package.mask/nvidia.conf"

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
            -gui -modemmanager -ppp'"'

        # Support a bunch of common video drivers.
        $sed -i -e '/^LLVM_TARGETS=/s/" *$/ AMDGPU&/' "$buildroot/etc/portage/make.conf" "$portage/make.conf"
        echo 'USE="$USE llvm"' >> "$portage/make.conf"
        echo "VIDEO_CARDS=\"amdgpu fbdev i915 intel nouveau${options[nvidia]:+ nvidia} panfrost radeon radeonsi qxl\"" >> "$portage/make.conf"
        packages+=(media-libs/libva-intel-driver)

        # Install VLC.
        $cat << 'EOF' >> "$portage/package.use/vlc.conf"
dev-qt/qtgui:5 -dbus
dev-qt/qtwidgets:5 -dbus -gtk
media-video/vlc gui -vdpau
sys-libs/zlib minizip
EOF
        packages+=(media-video/vlc)
}

function customize_buildroot() {
        # Enable flags for instruction sets supported by this CPU.
        test -x /usr/bin/cpuid2cpuflags &&
        cpuid2cpuflags | sed -n 's/^\([^ :]*\): \(.*\)/\1="\2"/p' >> "/usr/${options[host]}/etc/portage/make.conf"

        # Bundle x86 early microcode updates into the kernel for no initrd.
        [[ ${options[arch]:-$DEFAULT_ARCH} == *[3-6x]86* ]] &&
        echo "CONFIG_EXTRA_FIRMWARE=\"$(cd /lib/firmware && echo *-ucode/*)\"" >> /etc/kernel/config.d/firmware.config

        # Build less useless stuff on the host from bad dependencies.
        echo >> /etc/portage/make.conf 'USE="$USE' \
            -cups -debug -emacs -geolocation -gstreamer -llvm -oss -perl -python -sendmail -X'"'

        # Block terribly broken binutils-config from deleting all libraries.
        ln -fns /bin/true /usr/bin/binutils-config
}

function customize() {
        drop_development
        store_home_on_var +root

        echo "desktop-${options[distro]}" > root/etc/hostname

        # Drop extra unused paths.
        exclude_paths+=(
                usr/lib/firmware/{'*-ucode',liquidio,mellanox,mrvl,netronome,qcom,qed}
                usr/local
                usr/share/qemu/'*'{aarch,arm,hppa,ppc,riscv,s390,sparc}'*'
        )

        # Sign kernel modules manually since the dist-kernel package is weird.
        find root/lib/modules -name '*.ko.zst' -exec unzstd --rm {} ';'
        find root/lib/modules -name '*.ko' -exec \
            "/usr/${options[host]}/usr/src/linux/scripts/sign-file" \
            sha512 "$keydir/sign.key" "$keydir/sign.crt" {} ';'

        # Make NVIDIA use kernel mode setting and the page attribute table.
        opt nvidia && cat << 'EOF' > root/usr/lib/modprobe.d/nvidia-config.conf
options nvidia NVreg_UsePageAttributeTable=1
options nvidia-drm modeset=1
softdep nvidia post: nvidia-uvm
EOF

        # Support an executable VM image for quick testing.
        cat << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu
exec qemu-kvm -nodefaults \
    -machine q35 -cpu host -m 8G -vga std -nic user,model=virtio-net-pci \
    -drive file=/usr/share/edk2/ovmf/OVMF_CODE.fd,format=raw,if=pflash,read-only=on \
    -drive file="${IMAGE:-gpt.img}",format=raw,media=disk,snapshot=on \
    -device intel-hda -device hda-output \
    "$@"
EOF
}
