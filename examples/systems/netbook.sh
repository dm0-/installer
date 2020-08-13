        app-arch/cpio
        media-sound/pulseaudio
        x11-wm/windowmaker

        # Produce a U-Boot script and kernel image in this script.
        dev-embedded/u-boot-tools
        # Build a static QEMU user binary for the target CPU.
        packages_buildroot+=(app-emulation/qemu)
        $cat << 'EOF' >> "$buildroot/etc/portage/package.use/qemu.conf"
app-emulation/qemu qemu_user_targets_arm static-user
dev-libs/glib static-libs
dev-libs/libpcre static-libs
sys-apps/attr static-libs
sys-libs/zlib static-libs
EOF

        # Build ARM U-Boot GRUB for bootloader testing.
        packages_buildroot+=(sys-boot/grub)
        echo >> "$portage/make.conf" 'USE="$USE' \
            curl dbus elfutils gcrypt gdbm git gmp gnutls gpg http2 libnotify libxml2 mpfr nettle ncurses pcre2 readline sqlite udev uuid xml \
            bidi fribidi harfbuzz icu idn libidn2 nls truetype unicode \
            a52 aom dav1d dvd libaom mpeg theora vpx x265 \
            dynamic-loading hwaccel postproc startup-notification toolkit-scroll-bars user-session wide-int \
        # Disable LTO for packages broken with this architecture/ABI.
        echo 'media-libs/opus no-lto.conf' >> "$portage/package.env/no-lto.conf"
        echo 'app-editors/emacs -X' >> "$portage/package.use/emacs.conf"
        make -C /usr/src/linux -j"$(nproc)" "${dtb##*/}" \
# Support adding swap space.
CONFIG_SWAP=y
CONFIG_SND_USB=y
CONFIG_HID_GYRATION=m   # wireless mouse and keyboard
CONFIG_SND_USB_AUDIO=m  # headsets
CONFIG_USB_ACM=m        # fit-PC status LED
CONFIG_USB_HID=m        # mice and keyboards