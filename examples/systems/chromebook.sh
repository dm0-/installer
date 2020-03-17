        sys-apps/diffutils
        sys-devel/patch
            -e '/^COMMON_FLAGS=/s/[" ]*$/ -march=armv7ve+simd -mtune=cortex-a17 -mfpu=neon-vfpv4 -ftree-vectorize&/' \
        echo -e 'CPU_FLAGS_ARM="edsp neon thumb thumb2 v4 v5 v6 v7 vfp vfp-d32 vfpv3 vfpv4"\nUSE="$USE neon"' >> "$portage/make.conf"
            curl dbus gcrypt gdbm git gmp gnutls gpg libnotify libxml2 mpfr nettle ncurses pcre2 readline sqlite udev uuid \
            fribidi icu idn libidn2 nls unicode \
            alsa libsamplerate mp3 ogg pulseaudio sndfile sound speex theora vorbis vpx \
            acl caps cracklib fprint hardened pam seccomp smartcard xattr xcsecurity \
            acpi dri gallium kms libglvnd libkms opengl usb uvm vaapi vdpau wps \
            cairo gtk3 pango plymouth X xa xcb xft xinerama xkb xorg xrandr xvmc \
            dynamic-loading hwaccel postproc secure-delete startup-notification toolkit-scroll-bars wide-int \
            -cups -debug -emacs -fortran -geolocation -gtk -gtk2 -introspection -llvm -oss -perl -python -sendmail -tcpd -vala'"'
            -cups -debug -emacs -fortran -gallium -geolocation -gtk -gtk2 -introspection -llvm -oss -perl -python -sendmail -tcpd -vala -X'"'
        # Disable LTO for packages broken with this architecture/ABI.
        $cat << 'EOF' >> "$portage/package.env/no-lto.conf"
media-libs/freetype no-lto.conf
media-libs/libvpx no-lto.conf
EOF

        # Install Emacs as a terminal application.
        fix_package emacs
        packages+=(app-editors/emacs)
        echo 'USE="$USE emacs gzip-el"' >> "$portage/make.conf"
        $cat << 'EOF' >> "$portage/package.use/emacs.conf"
app-editors/emacs -X
dev-util/desktop-file-utils -emacs
dev-vcs/git -emacs
CONFIG_POSIX_MQUEUE=y
CONFIG_SYSVIPC=y
CONFIG_IPC_NS=y
CONFIG_NET_NS=y
# Support mounting disk images.
CONFIG_BLK_DEV=y
CONFIG_BLK_DEV_LOOP=y
# Support some optional systemd functionality.
CONFIG_COREDUMP=y
CONFIG_MAGIC_SYSRQ=y
CONFIG_NET_SCHED=y
CONFIG_NET_SCH_DEFAULT=y
CONFIG_NET_SCH_FQ_CODEL=y