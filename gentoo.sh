# SPDX-License-Identifier: GPL-3.0-or-later
packages=()
packages_buildroot=()

function create_buildroot() {
        local -r arch=${options[arch]:=$DEFAULT_ARCH}
        local -r profile=${options[profile]-$(archmap_profile "$arch")}
        local -r stage3=${options[stage3]:-$(archmap_stage3)}
        local -r host=${options[host]:=$arch-${options[distro]}-linux-gnu$([[ $arch == arm* ]] && echo eabi$([[ $arch == armv[67]* ]] && echo hf))}

        opt bootable || opt selinux && packages_buildroot+=(sys-kernel/gentoo-sources)
        opt gpt && opt uefi && packages_buildroot+=(sys-fs/dosfstools sys-fs/mtools)
        opt ramdisk || opt selinux || opt verity_sig && packages_buildroot+=(app-arch/cpio)
        opt read_only && ! opt squash && packages_buildroot+=(sys-fs/erofs-utils)
        opt secureboot && packages_buildroot+=(app-crypt/pesign dev-libs/nss)
        opt selinux && packages_buildroot+=(app-emulation/qemu)
        opt squash && packages_buildroot+=(sys-fs/squashfs-tools)
        opt uefi && packages_buildroot+=('<gnome-base/librsvg-2.41' media-gfx/imagemagick x11-themes/gentoo-artwork)
        opt verity && packages_buildroot+=(sys-fs/cryptsetup)
        packages_buildroot+=(dev-util/debugedit)

        $mkdir -p "$buildroot"
        $curl -L "$stage3.DIGESTS.asc" > "$output/digests"
        $curl -L "$stage3" > "$output/stage3.tar.xz"
        verify_distro "$output/digests" "$output/stage3.tar.xz"
        $tar -C "$buildroot" -xJf "$output/stage3.tar.xz"
        $rm -f "$output/digests" "$output/stage3.tar.xz"

        # Write a portage profile common to the native host and target system.
        local portage="$buildroot/etc/portage"
        $mv "$portage" "$portage.stage3"
        $mkdir -p "$portage"/{env,make.profile,package.{accept_keywords,env,license,mask,unmask,use},profile/package.use.{force,mask},repos.conf}
        $cp -at "$portage" "$portage.stage3/make.conf"
        $cat << EOF >> "$portage/make.profile/parent"
gentoo:$(archmap_profile)
gentoo:targets/systemd$(
opt selinux && echo -e '\ngentoo:features/selinux')
EOF
        echo "$buildroot"/etc/env.d/gcc/config-* | $sed 's,.*/[^-]*-\(.*\),\nCBUILD="\1",' >> "$portage/make.conf"
        $cat << EOF >> "$portage/make.conf"
FEATURES="\$FEATURES multilib-strict parallel-fetch parallel-install xattr -merge-sync -network-sandbox -news -selinux"
GRUB_PLATFORMS="${options[uefi]:+efi-$([[ $arch =~ 64 ]] && echo 64 || echo 32)}"
INPUT_DEVICES="libinput"
LLVM_TARGETS="$(archmap_llvm "$arch")"
POLICY_TYPES="targeted"
USE="\$USE system-icu"
VIDEO_CARDS=""
EOF
        $cat << 'EOF' >> "$portage/package.accept_keywords/boot.conf"
# Accept boot-related utilities with no stable versions.
app-crypt/pesign ~*
sys-boot/vboot-utils ~*
EOF
        $cat << 'EOF' >> "$portage/package.accept_keywords/firefox.conf"
# Accept the latest (non-ESR) Firefox release.
dev-libs/nspr ~*
dev-libs/nss ~*
www-client/firefox ~*
EOF
        $cat << 'EOF' >> "$portage/package.accept_keywords/gnome.conf"
# Accept viable versions of GNOME packages.
gnome-base/* *
gnome-extra/* *
app-arch/gnome-autoar *
<app-i18n/ibus-1.5.24 ~*
dev-libs/libgweather *
gui-libs/libhandy *
media-gfx/gnome-screenshot *
media-libs/gsound *
net-libs/libnma *
net-libs/webkit-gtk *
net-wireless/gnome-bluetooth *
sci-geosciences/geocode-glib *
x11-libs/colord-gtk *
x11-terms/gnome-terminal *
x11-wm/mutter *
EOF
        $cat << 'EOF' >> "$portage/package.accept_keywords/linux.conf"
# Accept the newest kernel and SELinux policy.
sec-policy/* ~*
sys-kernel/gentoo-kernel ~*
sys-kernel/gentoo-sources ~*
sys-kernel/git-sources ~*
sys-kernel/linux-headers ~*
virtual/dist-kernel ~*
EOF
        $cat << 'EOF' >> "$portage/package.accept_keywords/rust.conf"
# Accept Rust users to bypass bad keywording.
dev-lang/rust *
dev-lang/spidermonkey *
dev-libs/gjs *
gnome-base/librsvg *
sys-auth/polkit *
virtual/rust *
x11-themes/adwaita-icon-theme *
EOF
        $cat << 'EOF' >> "$portage/package.license/ucode.conf"
# Accept CPU microcode licenses.
sys-firmware/intel-microcode intel-ucode
sys-kernel/linux-firmware linux-fw-redistributable no-source-code
EOF
        $cat << 'EOF' >> "$portage/package.mask/colord.conf"
# Stay on the stable branch of colord until cross-compiling is supported.
>=x11-misc/colord-1.4
EOF
        $cat << 'EOF' >> "$portage/package.unmask/rust.conf"
# Unmask Rust users to bypass bad architecture profiles.
dev-lang/rust
dev-lang/spidermonkey
dev-libs/gjs
gnome-base/librsvg
sys-auth/polkit
virtual/rust
x11-themes/adwaita-icon-theme
EOF
        $cat << 'EOF' >> "$portage/package.unmask/systemd.conf"
# Unmask systemd when SELinux is enabled.
gnome-base/*
gnome-extra/*
sys-apps/gentoo-systemd-integration
sys-apps/systemd
EOF
        $cat << 'EOF' >> "$buildroot/etc/portage/package.use/cdrtools.conf"
# Support file capabilities when making ISO images.
app-cdr/cdrtools caps
EOF
        $cat << 'EOF' >> "$portage/package.use/cryptsetup.conf"
# Choose nettle as the crypto backend.
sys-fs/cryptsetup nettle -gcrypt -kernel -openssl
# Skip LVM by default so it doesn't get installed for cryptsetup/veritysetup.
sys-fs/lvm2 device-mapper-only -thin
EOF
        $cat << 'EOF' >> "$portage/package.use/firefox.conf"
# Fix Firefox builds by preferring GCC over Clang.
www-client/firefox -clang
EOF
        $cat << 'EOF' >> "$portage/package.use/gtk.conf"
# Disable EOL GTK+ 2 by default.  It uses different flag names sometimes.
*/* -gtk2
media-libs/libcanberra -gtk
EOF
        $cat << 'EOF' >> "$portage/package.use/linux.conf"
# Disable trying to build an initrd since it won't run in a chroot.
sys-kernel/gentoo-kernel -initramfs
# Apply patches to support additional CPU optimizations.
sys-kernel/gentoo-sources experimental
EOF
        $cat << 'EOF' >> "$portage/package.use/llvm.conf"
# Make clang use its own linker by default.
sys-devel/clang default-lld
# Build gold support for LLVM to match binutils.
sys-devel/llvm gold
EOF
        $cat << 'EOF' >> "$portage/package.use/shadow.conf"
# Don't use shadow's built in cracklib support since PAM provides it.
sys-apps/shadow -cracklib
EOF
        $cat << 'EOF' >> "$portage/package.use/squashfs-tools.conf"
# Support zstd squashfs compression.
sys-fs/squashfs-tools zstd
EOF
        $cat << 'EOF' >> "$portage/package.use/sudo.conf"
# Prefer gcrypt's digest functions instead of those from sudo or OpenSSL.
app-admin/sudo gcrypt -ssl
EOF
        $cat << 'EOF' >> "$portage/profile/package.provided"
# These Python tools are not useful, and they pull in horrific dependencies.
app-admin/setools-9999
EOF
        $cat << 'EOF' >> "$portage/profile/package.use.mask/emacs.conf"
# Support Emacs browser widgets everywhere so Emacs can handle everything.
app-editors/emacs -xwidgets
EOF
        $cat << 'EOF' >> "$portage/profile/package.use.mask/rust.conf"
# Allow sharing LLVM and the native Rust for cross-bootstrapping.
dev-lang/rust -system-bootstrap -system-llvm
EOF
        $cat << 'EOF' >> "$portage/profile/use.mask"
# Mask support for insecure protocols.
sslv2
sslv3
EOF

        # Permit selectively toggling important features.
        echo -e '-selinux\n-static\n-static-libs' >> "$portage/profile/use.force"
        echo -e '-cet\n-clang\n-systemd' >> "$portage/profile/use.mask"

        # Write build environment modifiers for later use.
        echo "CTARGET=\"$host\"" >> "$portage/env/ctarget.conf"
        echo 'LDFLAGS="-lgcc_s $LDFLAGS"' >> "$portage/env/link-gcc_s.conf"
        $cat << 'EOF' >> "$portage/env/no-lto.conf"
CFLAGS="$CFLAGS -fno-lto"
CXXFLAGS="$CXXFLAGS -fno-lto"
FFLAGS="$FFLAGS -fno-lto"
FCFLAGS="$FCFLAGS -fno-lto"
EOF
        $cat << EOF >> "$portage/env/rust-map.conf"
I_KNOW_WHAT_I_AM_DOING_CROSS="yes"
RUST_CROSS_TARGETS="$(archmap_llvm "$arch"):$(archmap_rust "$arch"):$host"
EOF

        # Accept baselayout-2.7 to fix a couple target root issues.
        echo '<sys-apps/baselayout-2.8 ~*' >> "$portage/package.accept_keywords/baselayout.conf"
        # Accept opus-1.3.1 to fix SIMD intrinsics usage.
        echo '<media-libs/opus-1.3.2 ~*' >> "$portage/package.accept_keywords/opus.conf"

        write_unconditional_patches "$portage/patches"

        # Create the target portage profile based on the native root's.
        portage="$buildroot/usr/$host/etc/portage"
        $mkdir -p "${portage%/portage}"
        $cp -at "${portage%/portage}" "$buildroot/etc/portage"
        $cat << EOF > "$portage/make.profile/parent"
$(test -n "$profile" && echo "gentoo:$profile" || {
        generic=(base arch/base default/linux releases/17.0)
        IFS=$'\n' ; echo "${generic[*]/#/gentoo:}"
})
gentoo:targets/systemd$(
opt selinux && echo -e '\ngentoo:features/selinux')
EOF
        $sed -i -e '/^COMMON_FLAGS=/s/[" ]*$/ -ggdb -flto&/' "$portage/make.conf"
        $cat <(echo) - << EOF >> "$portage/make.conf"
CHOST="$host"
GOARCH="$(archmap_go "$arch")"$(
[[ $arch == i[3-5]86 ]] && echo -e '\nGO386="softfloat"'
[[ $arch == armv[5-7]* ]] && echo -e "\nGOARM=\"${arch:4:1}\"")
RUST_TARGET="$(archmap_rust "$arch")"
EOF
        $cat << 'EOF' >> "$portage/make.conf"
ROOT="/usr/$CHOST"
BINPKG_COMPRESS="zstd"
BINPKG_COMPRESS_FLAGS="--fast --threads=0"
FEATURES="$FEATURES buildpkg compressdebug installsources pkgdir-index-trusted splitdebug"
PKG_INSTALL_MASK="$PKG_INSTALL_MASK .keep*dir .keep_*_*-*"
PKGDIR="$ROOT/var/cache/binpkgs"
PYTHON_TARGETS="$PYTHON_SINGLE_TARGET"
SYSROOT="$ROOT"
USE="$USE -kmod -multiarch -static -static-libs"
EOF
        $cat << 'EOF' >> "$portage/package.use/kill.conf"
# Use the kill command from util-linux to minimize systemd dependencies.
sys-apps/util-linux kill
sys-process/procps -kill
EOF
        $cat << 'EOF' >> "$portage/package.use/nftables.conf"
# Use the newer backend in iptables without switching applications to nftables.
net-firewall/iptables nftables
EOF
        $cat << 'EOF' >> "$portage/package.use/portage.conf"
# Cross-compiling portage native extensions is unsupported.
sys-apps/portage -native-extensions
EOF
        $cat << 'EOF' >> "$portage/package.use/sqlite.conf"
# Always enable secure delete for SQLite.
dev-db/sqlite secure-delete
EOF
        echo 'EXTRA_EMAKE="GDBUS_CODEGEN=/usr/bin/gdbus-codegen GLIB_MKENUMS=/usr/bin/glib-mkenums"' >> "$portage/env/cross-emake-utils.conf"
        echo 'GLIB_COMPILE_RESOURCES="/usr/bin/glib-compile-resources"' >> "$portage/env/cross-glib-compile-resources.conf"
        echo 'GLIB_GENMARSHAL="/usr/bin/glib-genmarshal"' >> "$portage/env/cross-glib-genmarshal.conf"
        echo 'GLIB_MKENUMS="/usr/bin/glib-mkenums"' >> "$portage/env/cross-glib-mkenums.conf"
        echo 'CFLAGS="$CFLAGS -I$SYSROOT/usr/include/libnl3"' >> "$portage/env/cross-libnl.conf"
        echo 'CPPFLAGS="$CPPFLAGS -I$SYSROOT/usr/include/libusb-1.0"' >> "$portage/env/cross-libusb.conf"
        echo 'AT_M4DIR="m4"' >> "$portage/env/kbd.conf"
        echo "BUILD_PKG_CONFIG_LIBDIR=\"/usr/lib$([[ $DEFAULT_ARCH =~ 64 ]] && echo 64)/pkgconfig\"" >> "$portage/env/meson-pkgconfig.conf"
        echo 'EXTRA_ECONF="--with-sdkdir=/usr/include/xorg"' >> "$portage/env/xf86-sdk.conf"
        $cat << 'EOF' >> "$portage/package.env/fix-cross-compiling.conf"
# Adjust the environment for cross-compiling broken packages.
app-crypt/gnupg cross-libusb.conf
app-i18n/ibus cross-glib-genmarshal.conf
dev-libs/dbus-glib cross-glib-genmarshal.conf
gnome-base/gnome-settings-daemon meson-pkgconfig.conf
gnome-base/librsvg cross-emake-utils.conf
net-libs/libmbim cross-emake-utils.conf
net-misc/modemmanager cross-emake-utils.conf
net-misc/networkmanager cross-emake-utils.conf
net-wireless/wpa_supplicant cross-libnl.conf
x11-drivers/xf86-input-libinput xf86-sdk.conf
x11-libs/gtk+ cross-glib-compile-resources.conf cross-glib-genmarshal.conf cross-glib-mkenums.conf
EOF
        echo 'sys-apps/kbd kbd.conf' >> "$portage/package.env/kbd.conf"
        $cat << 'EOF' >> "$portage/package.env/no-lto.conf"
# Turn off LTO for broken packages.
dev-libs/icu no-lto.conf
dev-libs/libaio no-lto.conf
dev-libs/libbsd no-lto.conf
media-gfx/potrace no-lto.conf
media-libs/alsa-lib no-lto.conf
media-sound/pulseaudio no-lto.conf
sys-apps/sandbox no-lto.conf
sys-libs/libselinux no-lto.conf
sys-libs/libsemanage no-lto.conf
sys-libs/libsepol no-lto.conf
x11-drivers/xf86-video-intel no-lto.conf
EOF
        echo split-usr >> "$portage/profile/use.mask"

        # Write portage profile settings that only apply to the native root.
        portage="$buildroot/etc/portage"
        # Preserve bindist in the build root, and don't build documentation.
        $sed -i -e '/^USE=/s/USE /&-doc bindist /' "$portage/make.conf"
        # Compile GRUB modules for the target system.
        echo 'sys-boot/grub ctarget.conf' >> "$portage/package.env/grub.conf"
        # Support cross-compiling Rust projects.
        test "x$(archmap_rust)" = "x$(archmap_rust "$arch")" ||
        echo 'dev-lang/rust rust-map.conf' >> "$portage/package.env/rust.conf"
        # Link a required library for building the SELinux labeling initrd.
        echo 'sys-fs/squashfs-tools link-gcc_s.conf' >> "$portage/package.env/squashfs-tools.conf"
        # Skip systemd for busybox since the labeling initrd has no real init.
        echo 'sys-apps/busybox -selinux -systemd' >> "$portage/package.use/busybox.conf"
        # Rust isn't built into the stage3 to bootstrap, but it can share LLVM.
        echo 'dev-lang/rust system-llvm -system-bootstrap' >> "$portage/package.use/rust.conf"
        # Disable journal compression to skip the massive cmake dependency.
        echo 'sys-apps/systemd -lz4' >> "$portage/package.use/systemd.conf"
        # Support building the UEFI logo image and signing tools.
        opt uefi && $cat << 'EOF' >> "$portage/package.use/uefi.conf"
dev-libs/nss utils
media-gfx/imagemagick svg xml
EOF
        # Work around bad dependencies requiring X on the host.
        $cat << 'EOF' >> "$portage/package.use/X.conf"
dev-qt/qtgui X
media-libs/libepoxy X
media-libs/libglvnd X
media-libs/mesa X
x11-libs/cairo X
x11-libs/gtk+ X
x11-libs/libxkbcommon X
EOF
        # Prevent accidentally disabling required modules.
        echo 'dev-libs/libxml2 python' >> "$portage/profile/package.use.force/libxml2.conf"

        # Write a portage script for querying USE flags later.
        $cat << 'EOF' > "$buildroot/usr/bin/using"
#!/usr/bin/env python3
import portage, sys
def using(atom, flags):
    settings = portage.config(clone=portage.settings)
    matches = portage.portdb.match(atom)
    if len(matches) >= 1:
        settings.setcpv(portage.best(matches), mydb=portage.portdb)
    return {f for f in settings.get('PORTAGE_USE', '').split() if f in flags} == flags
sys.exit(2 if len(sys.argv) < 3 else 0 if using(sys.argv[1], set(sys.argv[2:])) else 1)
EOF
        $chmod 0755 "$buildroot/usr/bin/using"

        # Write cross-clang wrappers.  They'll fail if clang isn't installed.
        $cat << 'EOF' > "$buildroot/usr/bin/${options[host]}-clang"
#!/bin/sh -eu
name="${0##*/}"
host="${name%-*}"
prog="/usr/lib/llvm/11/bin/${name##*-}"
exec "$prog" --sysroot="/usr/$host" --target="$host" "$@"
EOF
        $chmod 0755 "$buildroot/usr/bin/${options[host]}-clang"
        $ln -fn "$buildroot/usr/bin/${options[host]}-clang"{,++}

        # Work around bad PolicyKit dependencies.
        $mkdir -p "$buildroot/usr/share/gettext/its"
        $ln -fst "$buildroot/usr/share/gettext/its" \
            "/usr/${options[host]}/usr/share/gettext/its"/polkit.{its,loc}

        write_base_kernel_config
        initialize_buildroot "$@"

        script "$host" "${packages_buildroot[@]}" << 'EOF'
host=$1 ; shift

# Fetch the latest package definitions, and fix them.
emerge-webrsync
## Support cross-compiling musl (#732482).
sed -i -e '/ -e .*ld-musl/d' /var/db/repos/gentoo/sys-libs/musl/musl-*.ebuild
for ebuild in /var/db/repos/gentoo/sys-libs/musl/musl-*.ebuild ; do ebuild "$ebuild" manifest ; done
## Support cross-compiling with LLVM on EAPI 7 (#745744).
sed -i -e '/llvm_path=/s/x "/x $([[ $EAPI == 6 ]] || echo -b) "/' /var/db/repos/gentoo/eclass/llvm.eclass
## Support compiling basic qt5 packages in a sysroot.
sed -i -e '/^DEPEND=/iBDEPEND="~dev-qt/qtcore-${PV}"' /var/db/repos/gentoo/dev-qt/qtgui/qtgui-*.ebuild
sed -i -e '/^DEPEND=/iBDEPEND="~dev-qt/qtgui-${PV}"' /var/db/repos/gentoo/dev-qt/qtwidgets/qtwidgets-*.ebuild
sed -i -e '/^DEPEND=/iBDEPEND="~dev-qt/qtwidgets-${PV}"' /var/db/repos/gentoo/dev-qt/qtsvg/qtsvg-*.ebuild
sed -i -e '/^DEPEND=/iBDEPEND="~dev-qt/qtwidgets-${PV}"' /var/db/repos/gentoo/dev-qt/qtx11extras/qtx11extras-*.ebuild
for ebuild in /var/db/repos/gentoo/dev-qt/qt{gui,widgets,svg,x11extras}/qt*.ebuild ; do ebuild "$ebuild" manifest ; done
sed -i -e '/conf=/a${SYSROOT:+-extprefix "${QT5_PREFIX}" -sysroot "${SYSROOT}"}' -e 's/ OBJDUMP /&PKG_CONFIG /;/OBJCOPY/{p;s/OBJCOPY/PKG_CONFIG/g;}' /var/db/repos/gentoo/eclass/qt5-build.eclass
## Support erofs-utils (#701284).
if test "x$*" != "x${*/erofs-utils}"
then
        mkdir -p /var/cache/distfiles /var/db/repos/gentoo/sys-fs/erofs-utils
        curl -L 'https://701284.bugs.gentoo.org/attachment.cgi?id=712905' > /var/db/repos/gentoo/sys-fs/erofs-utils/erofs-utils-1.3.ebuild
        test x$(sha256sum /var/db/repos/gentoo/sys-fs/erofs-utils/erofs-utils-1.3.ebuild | sed -n '1s/ .*//p') = x1fba80f68f88494061f8f478be686fe29ec99f9ae40b22d08c89e020fe4bba41
        curl -L 'https://git.kernel.org/pub/scm/linux/kernel/git/xiang/erofs-utils.git/snapshot/erofs-utils-1.3.tar.gz' > /var/cache/distfiles/erofs-utils-1.3.tar.gz
        test x$(sha256sum /var/cache/distfiles/erofs-utils-1.3.tar.gz | sed -n '1s/ .*//p') = x132635740039bbe76d743aea72378bfae30dbf034e123929f5d794198d4c0b12
        ebuild /var/db/repos/gentoo/sys-fs/erofs-utils/erofs-utils-1.3.ebuild manifest --force
fi
# Restore the colord stable branch.
curl -L 'https://raw.githubusercontent.com/gentoo/gentoo/07fda8151b11d904d0b90b82fb87904ab547256f^/x11-misc/colord/colord-1.3.5.ebuild' > /var/db/repos/gentoo/x11-misc/colord/colord-1.3.5.ebuild
test x$(sha256sum /var/db/repos/gentoo/x11-misc/colord/colord-1.3.5.ebuild | sed -n '1s/ .*//p') = x06d50b69650b88b379e94a85e503fa381d30301801b2eb936a71b735427192a1
curl -L 'https://www.freedesktop.org/software/colord/releases/colord-1.3.5.tar.xz' > /var/cache/distfiles/colord-1.3.5.tar.xz
test x$(sha256sum /var/cache/distfiles/colord-1.3.5.tar.xz | sed -n '1s/ .*//p') = x2daa8ffd2a532d7094927cd1a4af595b8310cea66f7707edcf6ab743460feed2
ebuild /var/db/repos/gentoo/x11-misc/colord/colord-1.3.5.ebuild manifest --force

# Update the native build root packages to the latest versions.
emerge --changed-use --deep --jobs=4 --update --verbose --with-bdeps=y \
    @world sys-devel/crossdev

# Ensure Python defaults to the version in the profile before continuing.
sed -i -e '/^[^#]/d' /etc/python-exec/python-exec.conf
portageq envvar PYTHON_SINGLE_TARGET |
sed s/_/./g >> /etc/python-exec/python-exec.conf

# Create the cross-compiler toolchain in the native build root.
cat << 'EOG' >> /etc/portage/repos.conf/crossdev.conf
[crossdev]
location = /var/db/repos/crossdev
EOG
mkdir -p /usr/"$host"/usr/{bin,lib,lib32,lib64,libx32,src}
ln -fns bin /usr/"$host"/usr/sbin
ln -fst "/usr/$host" usr/{bin,lib,lib32,lib64,libx32,sbin}
stable=$(env {PORTAGE_CONFIG,,SYS}ROOT="/usr/$host" portageq envvar ACCEPT_KEYWORDS | grep -Fqs -e '~' -e '**' || echo 1)
crossdev ${stable:+--stable} --target "$host"

# Install all requirements for building the target image.
exec emerge --changed-use --jobs=4 --update --verbose "$@"
EOF

        build_relabel_kernel
}

function install_packages() {
        local -rx {PORTAGE_CONFIG,,SYS}ROOT="/usr/${options[host]}"
        local -a packages_sysroot=()

        opt bootable || opt networkd && packages+=(acct-group/mail sys-apps/systemd)
        opt selinux && packages+=(sec-policy/selinux-base-policy)
        packages+=(sys-apps/baselayout)

        # If system-specific kernel configs were not given, use dist-kernel.
        if opt bootable
        then
                test "x$(cd /etc/kernel/config.d ; compgen -G '*.config')" \
                    = xbase.config || : ${options[raw_kernel]=1}
                cat << EOF >> /etc/kernel/config.d/keys.config
CONFIG_MODULE_SIG_KEY="$keydir/sign.pem"
$(opt verity_sig || echo '#')CONFIG_SYSTEM_TRUSTED_KEYS="$keydir/verity.crt"
EOF
                if ! opt raw_kernel
                then
                        chgrp portage "$keydir" ; chmod g+x "$keydir"
                        packages_sysroot+=(sys-kernel/gentoo-kernel virtual/libelf)
                fi
        fi

        # Build an unpackaged kernel now so external modules can use its files.
        if opt raw_kernel
        then
                local -r kernel_arch="$(archmap_kernel "${options[arch]}")"
                KCONFIG_CONFIG=/root/config \
                /usr/src/linux/scripts/kconfig/merge_config.sh \
                    -m -r /etc/kernel/config.d/*.config
                make -C /usr/src/linux -j"$(nproc)" \
                    allnoconfig KCONFIG_ALLCONFIG=/root/config \
                    ARCH="$kernel_arch" CROSS_COMPILE="${options[host]}-" V=1
                make -C /usr/src/linux -j"$(nproc)" \
                    ARCH="$kernel_arch" CROSS_COMPILE="${options[host]}-" V=1
                ln -fst "$ROOT/usr/src" ../../../../usr/src/linux
                cat << 'EOF' >> "$ROOT/etc/portage/profile/package.provided"
# The kernel source is shared between the host and cross-compiled root.
sys-kernel/gentoo-sources-9999
EOF
        fi < /dev/null

        # Build the cross-compiled toolchain packages first.
        COLLISION_IGNORE='*' USE=-selinux emerge --jobs=4 --oneshot --verbose \
            sys-devel/gcc virtual/libc virtual/os-headers
        packages+=(sys-devel/gcc virtual/libc)  # Install libstdc++ etc.

        # Cheat bootstrapping packages with circular dependencies.
        USE='-* drm kill nettle truetype' emerge --changed-use --jobs=4 --oneshot --verbose \
            $(using media-libs/freetype harfbuzz && echo media-libs/harfbuzz) \
            $(using media-libs/libwebp tiff && using media-libs/tiff webp && echo media-libs/libwebp) \
            $(using sys-fs/cryptsetup udev || using sys-fs/lvm2 udev && using sys-apps/systemd cryptsetup && echo sys-fs/cryptsetup) \
            $(using sys-libs/libcap pam && using sys-libs/pam filecaps && echo sys-libs/libcap) \
            $(using media-libs/mesa gallium vaapi && using x11-libs/libva opengl && echo x11-libs/libva) \
            sys-apps/util-linux

        # Cross-compile everything and make binary packages for the target.
        emerge --changed-use --deep --jobs=4 --update --verbose --with-bdeps=y \
            "${packages[@]}" "${packages_sysroot[@]}" "$@"

        # Install the target root from binaries with no build dependencies.
        mkdir -p root/{dev,etc,home,proc,run,srv,sys,usr/{bin,lib},var}
        mkdir -pm 0700 root/root
        ln -fns bin root/usr/sbin
        if [[ ${options[arch]-} =~ 64 ]]
        then
                [[ ${options[host]-} == *x32 ]] &&
                mkdir -p root/usr/libx32 ||
                ln -fns lib root/usr/lib64
        fi
        (cd root ; exec ln -fst . usr/*)
        ln -fns .. "root$ROOT"  # Lazily work around bad packaging.
        emerge --{,sys}root=root --jobs="$(nproc)" -1Kv "${packages[@]}" "$@"
        mv -t root/usr/bin root/gcc-bin/*/* ; rm -fr root/{binutils,gcc}-bin

        # Create a UTF-8 locale so things work.
        localedef --prefix=root -c -f UTF-8 -i en_US en_US.UTF-8

        # If a modular kernel was configured, install the stripped modules.
        opt raw_kernel && grep -Fqsx CONFIG_MODULES=y /usr/src/linux/.config &&
        make -C /usr/src/linux modules_install \
            INSTALL_MOD_PATH=/wd/root INSTALL_MOD_STRIP=1 \
            ARCH="$kernel_arch" CROSS_COMPILE="${options[host]}-" V=1

        # List everything installed in the image and what was used to build it.
        qlist -CIRSSUv > packages-sysroot.txt
        qlist --root=/ -CIRSSUv > packages-buildroot.txt
        qlist --root=root -CIRSSUv > packages.txt
}

function distro_tweaks() {
        rm -fr root/etc/init.d root/etc/kernel
        ln -fns ../lib/systemd/systemd root/usr/sbin/init
        ln -fns ../proc/self/mounts root/etc/mtab

        sed -i -e 's/PS1+=..[[]/&\\033[01;33m\\]$? \\[/;/\$ .$/s/PS1+=./&$? /' root/etc/bash/bashrc
        echo "alias ll='ls -l'" >> root/etc/skel/.bashrc

        # Without GDB, assume debuginfo is unwanted to be like other distros.
        test -x root/usr/bin/gdb && : ${options[debuginfo]=1}
        opt debuginfo || drop_debugging

        # Add a mount point to support the ESP mount generator.
        opt uefi && mkdir root/boot

        # Create some usual stuff in /var that is missing.
        echo 'd /var/empty' > root/usr/lib/tmpfiles.d/var-compat.conf
        test -s root/usr/lib/sysusers.d/acct-user-polkitd.conf &&
        echo 'd /var/lib/polkit-1 - polkitd polkitd' >> root/usr/lib/tmpfiles.d/polkit.conf

        # Conditionalize wireless interfaces on their configuration files.
        test -s root/usr/lib/systemd/system/wpa_supplicant-nl80211@.service &&
        sed -i \
            -e '/^\[Unit]/aConditionFileNotEmpty=/etc/wpa_supplicant/wpa_supplicant-nl80211-%I.conf' \
            root/usr/lib/systemd/system/wpa_supplicant-nl80211@.service

        # The targeted policy seems more realistic to get working first.
        test -s root/etc/selinux/config &&
        sed -i -e '/^SELINUXTYPE=/s/=.*/=targeted/' root/etc/selinux/config

        # The targeted policy does not support a sensitivity level.
        sed -i -e 's/t:s0/t/g' root/usr/lib/systemd/system/*.mount

        # Perform case-insensitive searches in less by default.
        test -s root/etc/env.d/70less &&
        sed -i -e '/^LESS=/s/[" ]*$/ -i&/' root/etc/env.d/70less

        # Default to the nftables firewall interface if it was built.
        ROOT=root eselect iptables list |& grep -Fqs xtables-nft-multi &&
        ROOT=root eselect iptables set xtables-nft-multi

        # Set some sensible key behaviors for a bare X session.
        test -x root/usr/bin/startx &&
        mkdir -p root/etc/X11/xorg.conf.d &&
        cat << 'EOF' > root/etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbOptions" "ctrl:nocaps"
EndSection
EOF

        # Prioritize available daemons for the user audio service socket.
        local dir=root/usr/lib/systemd/user
        local daemon ; for daemon in pipewire-pulse pulseaudio
        do
                if test -s "$dir/$daemon.socket"
                then
                        mkdir -p "$dir/sockets.target.wants"
                        ln -fst "$dir/sockets.target.wants" "../$daemon.socket"
                        break
                fi
        done
        test -s "$dir/pipewire.socket" &&
        ln -fst "$dir/sockets.target.wants" ../pipewire.socket

        # Select a default desktop environment for startx, or default to twm.
        local wm ; for wm in Xfce4 wmaker
        do
                if test -s "root/etc/X11/Sessions/$wm"
                then
                        echo "XSESSION=$wm" > root/etc/env.d/90xsession
                        break
                fi
        done

        # Magenta looks more "Gentoo" than green, as in the website and logo.
        sed -i -e '/^ANSI_COLOR=/s/32/35/' root/etc/os-release
}

# Override ramdisk creation to support a builtin initramfs for Gentoo.
eval "$(declare -f squash | $sed 's/zstd --[^;]*/if opt monolithic ; then cat > /root/initramfs.cpio ; else & ; fi/')"

function save_boot_files() if opt bootable
then
        local -rx {PORTAGE_CONFIG,,SYS}ROOT="/usr/${options[host]}"
        opt uefi && USE=gnuefi emerge --buildpkg=n --changed-use --jobs=4 --oneshot --verbose sys-apps/systemd
        opt uefi && test ! -s logo.bmp &&
        sed '/namedview/,/<.g>/d' /usr/share/pixmaps/gentoo/misc/svg/GentooWallpaper_2.svg > /root/logo.svg &&
        magick -background none /root/logo.svg -trim -color-matrix '0 1 0 0 0 0 0 1 0 0 0 0 0 0 1 0 0 0 1 0 1 0 0 0 0' logo.bmp
        test -s $(opt monolithic && echo /root/initramfs.cpio || echo initrd.img) || build_busybox_initrd
        opt monolithic && if opt raw_kernel
        then cat >> /usr/src/linux/.config
        else cat >> /etc/kernel/config.d/monolithic.config
        fi << EOF
CONFIG_CMDLINE="$(sed 's/["\]/\\&/g' kernel_args.txt)"
CONFIG_CMDLINE_FORCE=y
CONFIG_INITRAMFS_COMPRESSION_ZSTD=y
CONFIG_INITRAMFS_FORCE=y
$(test -s /root/initramfs.cpio || echo '#')CONFIG_INITRAMFS_SOURCE="/root/initramfs.cpio"
EOF
        test -s vmlinux -o -s vmlinuz || if opt raw_kernel
        then
                local -r arch="$(archmap_kernel "${options[arch]}")"
                if opt monolithic
                then
                        make -C /usr/src/linux -j"$(nproc)" olddefconfig \
                            ARCH="$arch" CROSS_COMPILE="${options[host]}-" V=1
                        make -C /usr/src/linux -j"$(nproc)" \
                            ARCH="$arch" CROSS_COMPILE="${options[host]}-" V=1
                fi
                make -C /usr/src/linux install \
                    ARCH="$arch" CROSS_COMPILE="${options[host]}-" V=1
                cp -p /boot/vmlinux-* vmlinux || cp -p /boot/vmlinuz-* vmlinuz
        else
                if opt monolithic
                then
                        chgrp portage /root ; chmod g+x /root
                        emerge --buildpkg=n --jobs=4 --oneshot --verbose \
                            sys-kernel/gentoo-kernel
                        chgrp root /root ; chmod g-x /root
                fi
                cp -p "$ROOT"/usr/src/linux/arch/*/boot/*Image* vmlinuz
        fi < /dev/null
fi

# Override the UEFI function to support non-native stub files in Gentoo.
eval "$(declare -f produce_uefi_exe | $sed \
    -e 's/objcopy/"${options[host]}-&"/' \
    -e 's,/[^ ]*.efi.stub,/usr/${options[host]}&,')"

function build_busybox_initrd() if opt ramdisk || opt verity_sig
then
        local -r root=$(mktemp --directory --tmpdir="$PWD" ramdisk.XXXXXXXXXX)
        mkdir -p "$root"/{bin,dev,proc,sys,sysroot}

        # Cross-compile minimal static tools required for the initrd.
        local -rx {PORTAGE_CONFIG,,SYS}ROOT="/usr/${options[host]}"
        opt verity && USE=static-libs \
        emerge --buildpkg=n --changed-use --jobs=4 --oneshot --verbose \
            dev-libs/libaio sys-apps/util-linux
        USE='-* device-mapper-only static' \
        emerge --buildpkg=n --jobs=4 --nodeps --oneshot --verbose \
            sys-apps/busybox \
            ${options[verity]:+sys-fs/lvm2} \
            ${options[verity_sig]:+sys-apps/keyutils}

        # Import the cross-compiled tools into the initrd root.
        cp -pt "$root/bin" "$ROOT/bin/busybox"
        local cmd ; for cmd in ash cat losetup mount mountpoint sleep switch_root
        do ln -fns busybox "$root/bin/$cmd"
        done
        opt verity && cp -p "$ROOT/sbin/dmsetup.static" "$root/bin/dmsetup"
        opt verity_sig && cp -pt "$root/bin" "$ROOT/bin/keyctl"

        # Write an init script and include required build artifacts.
        cat << EOF > "$root/init" && chmod 0755 "$root/init"
#!/bin/ash -eux
export PATH=/bin
mountpoint -q /dev || mount -nt devtmpfs devtmpfs /dev
mountpoint -q /proc || mount -nt proc proc /proc
mountpoint -q /sys || mount -nt sysfs sysfs /sys
$(opt ramdisk && echo "losetup ${options[read_only]:+-r }/dev/loop0 /root.img"
opt verity_sig && echo 'keyctl padd user verity:root @u < /verity.sig'
opt verity && cat << 'EOG' ||
dmv=" $(cat /proc/cmdline) "
dmv=${dmv##* \"DVR=} ; dmv=${dmv##* DVR=\"} ; dmv=${dmv%%\"*}
for attempt in 1 2 3 4 0
do dmsetup create --concise "$dmv" && break || sleep "$attempt"
done
mount -no ro /dev/mapper/root /sysroot
EOG
echo "mount -n${options[read_only]:+o ro} /dev/loop0 /sysroot")
exec switch_root /sysroot /sbin/init
EOF
        opt ramdisk && ln -fn final.img "$root/root.img"
        opt verity_sig && ln -ft "$root" verity.sig

        # Build the initrd.
        find "$root" -mindepth 1 -printf '%P\n' |
        cpio -D "$root" -H newc -R 0:0 -o |
        if opt monolithic
        then cat > /root/initramfs.cpio
        else zstd --threads=0 --ultra -22 > initrd.img
        fi
fi

function write_unconditional_patches() {
        local -r patches="$1"

        $mkdir -p "$patches/dev-lang/spidermonkey"
        $cat << 'EOF' > "$patches/dev-lang/spidermonkey/rust.patch"
--- a/build/moz.configure/rust.configure
+++ b/build/moz.configure/rust.configure
@@ -353,7 +353,7 @@
 
             return None
 
-        rustc_target = find_candidate(candidates)
+        rustc_target = os.getenv('RUST_TARGET') if host_or_target_str == 'target' and os.getenv('RUST_TARGET') is not None else find_candidate(candidates)
 
         if rustc_target is None:
             die("Don't know how to translate {} for rustc".format(
EOF

        $mkdir -p "$patches/www-client/firefox"
        $cat << 'EOF' > "$patches/www-client/firefox/rust.patch"
--- a/build/moz.configure/rust.configure
+++ b/build/moz.configure/rust.configure
@@ -491,12 +491,13 @@
     rustc, target, c_compiler, rust_supported_targets, arm_target, when=rust_compiler
 )
 @checking("for rust target triplet")
+@imports('os')
 def rust_target_triple(
     rustc, target, compiler_info, rust_supported_targets, arm_target
 ):
-    rustc_target = detect_rustc_target(
+    rustc_target = os.getenv('RUST_TARGET', detect_rustc_target(
         target, compiler_info, arm_target, rust_supported_targets
-    )
+    ))
     assert_rust_compile(target, rustc_target, rustc)
     return rustc_target
 
EOF
}

function write_base_kernel_config() if opt bootable
then
        $mkdir -p "$buildroot/etc/kernel/config.d"
        {
                echo '# Basic settings
CONFIG_ACPI=y
CONFIG_BASE_FULL=y
CONFIG_BLOCK=y
CONFIG_JUMP_LABEL=y
CONFIG_KERNEL_'$([[ ${options[arch]} =~ [3-6x]86 ]] && echo ZSTD || echo XZ)'=y
CONFIG_MULTIUSER=y
CONFIG_SHMEM=y
CONFIG_UNIX=y
# File system settings
CONFIG_DEVTMPFS=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_TMPFS=y
CONFIG_TMPFS_POSIX_ACL=y
# Executable settings
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
# Security settings
CONFIG_BPF_JIT=y
CONFIG_BPF_JIT_ALWAYS_ON=y
CONFIG_FORTIFY_SOURCE=y
CONFIG_HARDEN_BRANCH_PREDICTOR=y
CONFIG_HARDENED_USERCOPY=y
CONFIG_LOCK_DOWN_KERNEL_FORCE_CONFIDENTIALITY=y
CONFIG_RANDOMIZE_BASE=y
CONFIG_RANDOMIZE_MEMORY=y
CONFIG_RELOCATABLE=y
CONFIG_RETPOLINE=y
CONFIG_SECURITY_LOCKDOWN_LSM=y
CONFIG_SECURITY_LOCKDOWN_LSM_EARLY=y
CONFIG_STACKPROTECTOR=y
CONFIG_STACKPROTECTOR_STRONG=y
CONFIG_STRICT_KERNEL_RWX=y
CONFIG_VMAP_STACK=y
# Signing settings
CONFIG_MODULE_SIG=y
CONFIG_MODULE_SIG_ALL=y
CONFIG_MODULE_SIG_FORCE=y
CONFIG_MODULE_SIG_SHA512=y'
                [[ ${options[arch]} =~ 64 ]] && echo '# Architecture settings
CONFIG_64BIT=y'
                [[ ${options[arch]} = x86_64 ]] && echo 'CONFIG_SMP=y
CONFIG_X86_LOCAL_APIC=y' &&
                [[ ${options[host]} == *x32 ]] && echo 'CONFIG_X86_X32=y
CONFIG_IA32_EMULATION=y'
                opt networkd && echo '# Network settings
CONFIG_NET=y
CONFIG_INET=y
CONFIG_IPV6=y
CONFIG_PACKET=y'
                opt nvme && echo '# NVMe settings
CONFIG_PCI=y
CONFIG_BLK_DEV_NVME=y'
                opt ramdisk || opt verity_sig && echo '# Initrd settings
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_ZSTD=y'
                opt ramdisk && echo '# Loop settings
CONFIG_BLK_DEV=y
CONFIG_BLK_DEV_LOOP=y
CONFIG_BLK_DEV_LOOP_MIN_COUNT=1' || echo '# Loop settings
CONFIG_BLK_DEV_LOOP_MIN_COUNT=0'
                opt read_only && echo '# Overlay settings
CONFIG_OVERLAY_FS=y'
                opt selinux && echo '# SELinux settings
CONFIG_AUDIT=y
CONFIG_SECURITY=y
CONFIG_SECURITY_NETWORK=y
CONFIG_SECURITY_SELINUX=y
CONFIG_SECURITY_SELINUX_DEVELOP=y    # XXX: Start permissive.
CONFIG_SECURITY_SELINUX_BOOTPARAM=y  # XXX: Support toggling at boot to test.'
                opt squash && echo '# Squashfs settings
CONFIG_MISC_FILESYSTEMS=y
CONFIG_SQUASHFS=y
CONFIG_SQUASHFS_FILE_DIRECT=y
CONFIG_SQUASHFS_DECOMP_MULTI=y
CONFIG_SQUASHFS_XATTR=y
CONFIG_SQUASHFS_ZSTD=y' || { opt read_only && echo '# EROFS settings
CONFIG_MISC_FILESYSTEMS=y
CONFIG_EROFS_FS=y
CONFIG_EROFS_FS_XATTR=y
CONFIG_EROFS_FS_POSIX_ACL=y
CONFIG_EROFS_FS_SECURITY=y' ; } || echo '# Ext[2-4] settings
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_FS_SECURITY=y
CONFIG_EXT4_USE_FOR_EXT2=y'
                opt uefi && echo '# UEFI settings
CONFIG_EFI=y
CONFIG_EFI_STUB=y
# ESP settings
CONFIG_VFAT_FS=y
CONFIG_FAT_DEFAULT_UTF8=y
CONFIG_NLS=y
CONFIG_NLS_DEFAULT="utf8"
CONFIG_NLS_CODEPAGE_437=y
CONFIG_NLS_ISO8859_1=y
CONFIG_NLS_UTF8=y'
                opt verity && echo '# Verity settings
CONFIG_MD=y
CONFIG_BLK_DEV_DM=y
CONFIG_DM_INIT=y
CONFIG_DM_VERITY=y
CONFIG_CRYPTO_SHA256=y'
                opt verity_sig && echo 'CONFIG_CRYPTO_SHA512=y
CONFIG_DM_VERITY_VERIFY_ROOTHASH_SIG=y'
                echo '# Settings for systemd
CONFIG_COMPAT_32BIT_TIME=y
CONFIG_DMI=y
CONFIG_NAMESPACES=y
CONFIG_GENTOO_LINUX=y
CONFIG_GENTOO_LINUX_UDEV=y
CONFIG_GENTOO_LINUX_INIT_SYSTEMD=y
CONFIG_FILE_LOCKING=y
CONFIG_FUTEX=y
CONFIG_POSIX_TIMERS=y
CONFIG_PROC_SYSCTL=y
CONFIG_UNIX98_PTYS=y'
        } >> "$buildroot/etc/kernel/config.d/base.config"
fi

function build_relabel_kernel() if opt selinux
then
        echo > "$buildroot/root/config.relabel" '# Target the native CPU.
'$([[ $DEFAULT_ARCH =~ 64 ]] || echo '#')'CONFIG_64BIT=y
CONFIG_MNATIVE=y
CONFIG_SMP=y
# Support executing programs and scripts.
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y
# Support kernel file systems.
CONFIG_DEVTMPFS=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
# Support labeling the root file system.
CONFIG_BLOCK=y
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_SECURITY=y
# Support using an initrd.
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_ZSTD=y
# Support SELinux.
CONFIG_NET=y
CONFIG_AUDIT=y
CONFIG_MULTIUSER=y
CONFIG_SECURITY=y
CONFIG_SECURITY_NETWORK=y
CONFIG_INET=y
CONFIG_SECURITY_SELINUX=y
# Support initial SELinux labeling.
CONFIG_FUTEX=y
CONFIG_SECURITY_SELINUX_DEVELOP=y
# Support POSIX timers for mksquashfs.
CONFIG_POSIX_TIMERS=y
# Support the default hard drive in QEMU.
CONFIG_PCI=y
CONFIG_ATA=y
CONFIG_ATA_BMDMA=y
CONFIG_ATA_SFF=y
CONFIG_BLK_DEV_SD=y
CONFIG_ATA_PIIX=y
# Support a console on the default serial port in QEMU.
CONFIG_TTY=y
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
# Support powering off QEMU.
CONFIG_ACPI=y
# Print initialization messages for debugging.
CONFIG_PRINTK=y'
        script << 'EOF'
make -C /usr/src/linux -j"$(nproc)" V=1 \
    allnoconfig KCONFIG_ALLCONFIG=/root/config.relabel
make -C /usr/src/linux -j"$(nproc)" V=1
make -C /usr/src/linux install V=1
mv /boot/vmlinuz-* vmlinuz.relabel
rm -f /boot/*
exec make -C /usr/src/linux -j"$(nproc)" mrproper V=1
EOF
fi

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBEqUWzgBEACXftaG+HVuSQBEqdpBIg2SOVgWW/KbCihO5wPOsdbM93e+psmb
wvw+OtNHADQvxocKMuZX8Q/j5i3nQ/ikQFW5Oj6UXvl1qyxZhR2P7GZSNQxn0eMI
zAX08o691ws2/dFGXKmNT6btYJ0FxuTtTVSK6zi68WF+ILGK/O2TZXK9EKfZKPDH
KHcGrUq4c03vcGANz/8ksJj2ZYEGxMr1h7Wfe9PVcm0gCB1MhYHNR755M47V5Pch
fyxbs6vaKz82PgrNjjjbT0PISvnKReUOdA2PFUWry6UKQkiVrLVDRkd8fryLL8ey
5JxgVoJZ4echoVWQ0JYJ5lJTWmcZyxQYSAbz2w9dLB+dPyyGpyPp1KX1ADukbROp
9S11I9+oVnyGdUBm+AUme0ecekWvt4qiCw3azghLSwEyGZc4a8nNcwSqFmH7Rqdd
1+gHc+4tu4WHmguhMviifGXKyWiRERULp0obV33JEo/c4uwyAZHBTJtKtVaLb92z
aRdh1yox2I85iumyt62lq9dfOuet4NNVDnUkqMYCQD23JB8IM+qnVaDwJ6oCSIKi
nY3uyoqbVE6Lkm+Hk5q5pbvg1cpEH6HWWAl20EMCzMOoMcH0tPyQLDlD2Mml7veG
kwdy3S6RkjCympbNzqWec2+hkU2c93Bgpfh7QP0GDN0qrzcNNFmrD5795QARAQAB
tFNHZW50b28gTGludXggUmVsZWFzZSBFbmdpbmVlcmluZyAoQXV0b21hdGVkIFdl
ZWtseSBSZWxlYXNlIEtleSkgPHJlbGVuZ0BnZW50b28ub3JnPokCUgQTAQoAPAYL
CQgHAwIEFQIIAwMWAgECHgECF4ACGwMWIQQT672+3noSd139sbq7Vy4OLRgpEAUC
XMRr7wUJFGgDagAKCRC7Vy4OLRgpEMG6D/9ppsqaA6C8VXADtKnHYH77fb9SAsAY
YcDpZnT8wcfMlOTA7c5rEjNXuWW0BFNBi13CCPuThNbyLWiRhmlVfb6Mqp+J+aJc
rSHTQrBtByFDmXKnaljOrVKVej7uL+sdRen/tGhd3OZ5nw38fNID8nv7ZQiSlCQh
luKnfMDw/ukvPuzaTmVHEJ6udI0PvRznk3XgSb6ZSi2BZYHn1/aoDkKN9OswiroJ
pPpDAib9bzitb9FYMOWhra9Uet9akWnVxnM+XIK2bNkO2dbeClJMszN93r0BIvSu
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
yqu4wb67pwMX312ABdpW
=kSzn
-----END PGP PUBLIC KEY BLOCK-----
EOF
        $gpg --verify "$1"
        test x$($sed -n '/^[0-9a-f]/{s/ .*//p;q;}' "$1") = x$($sha512sum "$2" | $sed -n '1s/ .*//p')
}

function archmap() case "${*:-$DEFAULT_ARCH}" in
    aarch64)  echo arm64 ;;
    arm*)     echo arm ;;
    i[3-6]86) echo x86 ;;
    powerpc)  echo ppc ;;
    riscv64)  echo riscv ;;
    x86_64)   echo amd64 ;;
    *) return 1 ;;
esac

function archmap_go() case "${*:-$DEFAULT_ARCH}" in
    aarch64)  echo arm64 ;;
    arm*)     echo arm ;;
    i[3-6]86) echo 386 ;;
    riscv64)  echo riscv64 ;;
    x86_64)   echo amd64 ;;
    *) return 1 ;;
esac

function archmap_kernel() case "${*:-$DEFAULT_ARCH}" in
    aarch64)  echo arm64 ;;
    arm*)     echo arm ;;
    i[3-6]86) echo x86 ;;
    powerpc)  echo powerpc ;;
    riscv64)  echo riscv ;;
    x86_64)   echo x86 ;;
    *) return 1 ;;
esac

function archmap_llvm() case "${*:-$DEFAULT_ARCH}" in
    aarch64)  echo AArch64 ;;
    arm*)     echo ARM ;;
    i[3-6]86) echo X86 ;;
    powerpc)  echo PowerPC ;;
    riscv64)  echo RISCV ;;
    x86_64)   echo X86 ;;
    *) return 1 ;;
esac

function archmap_profile() {
        local -r nomulti=$(opt multilib || echo /no-multilib)
        case "${*:-$DEFAULT_ARCH}" in
            aarch64)  echo default/linux/arm64/17.0 ;;
            armv4t*)  echo default/linux/arm/17.0/armv4t ;;
            armv5te*) echo default/linux/arm/17.0/armv5te ;;
            armv6*j*) echo default/linux/arm/17.0/armv6j ;;
            armv7a)   echo default/linux/arm/17.0/armv7a ;;
            i[3-6]86) echo default/linux/x86/17.0/hardened ;;
            powerpc)  echo default/linux/ppc/17.0 ;;
            riscv64)  echo default/linux/riscv/17.0/rv64gc/lp64d ;;
            x86_64)   echo default/linux/amd64/17.1$nomulti/hardened ;;
            *) return 1 ;;
        esac
}

function archmap_rust() case "${*:-$DEFAULT_ARCH}" in
    aarch64)  echo aarch64-unknown-linux-gnu ;;
    armv4t*)  echo armv4t-unknown-linux-gnueabi ;;
    armv5te*) echo armv5te-unknown-linux-gnueabi ;;
    armv6*)   echo arm-unknown-linux-gnueabihf ;;
    armv7*)   echo armv7-unknown-linux-gnueabihf ;;
    i386)     echo i386-unknown-linux-gnu ;;
    i486)     echo i486-unknown-linux-gnu ;;
    i586)     echo i586-unknown-linux-gnu ;;
    i686)     echo i686-unknown-linux-gnu ;;
    powerpc)  echo powerpc-unknown-linux-gnu ;;
    riscv64)  echo riscv64gc-unknown-linux-gnu ;;
    x86_64)   echo x86_64-unknown-linux-gnu ;;
    *) return 1 ;;
esac

function archmap_stage3() {
        local -r arch=${*:-$DEFAULT_ARCH}
        local -r base="https://gentoo.osuosl.org/releases/$(archmap "$@")/autobuilds"
        local -r hardfp=$([[ $arch == armv[67]* ]] && echo _hardfp)
        local -r nomulti=$(opt multilib || echo +nomultilib)
        local -r selinux=${options[selinux]:+-selinux}

        local stage3
        case "$arch" in
            aarch64)  stage3=stage3-arm64-systemd ;;
            armv4tl)  stage3=stage3-armv4tl-systemd ;;
            armv5tel) stage3=stage3-armv5tel-systemd ;;
            armv6*j*) stage3=stage3-armv6j$hardfp-systemd ;;
            armv7a)   stage3=stage3-armv7a$hardfp-systemd ;;
            i[45]86)  stage3=stage3-i486 ;;
            i686)     stage3=stage3-i686-hardened ;;
            powerpc)  stage3=stage3-ppc ;;
            x86_64)   stage3=stage3-amd64-hardened$selinux$nomulti ;;
            *) return 1 ;;
        esac

        local -r build=$($curl -L "$base/latest-$stage3.txt" | $sed -n '/^[0-9]\{8\}T[0-9]\{6\}Z/{s/Z.*/Z/p;q;}')
        [[ $stage3 =~ hardened ]] && stage3="hardened/$stage3"
        echo "$base/$build/$stage3-$build.tar.xz"
}

# OPTIONAL (BUILDROOT)

function fix_package() {
        local -r portage="$buildroot/usr/${options[host]}/etc/portage"
        case "$*" in
            vlc)
                [[ ${options[arch]} =~ 64 ]] &&
                echo 'PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib64/pkgconfig:$SYSROOT/usr/share/pkgconfig"' >> "$portage/env/pkgconfig-redundant.conf" ||
                echo 'PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"' >> "$portage/env/pkgconfig-redundant.conf"
                echo 'dev-qt/* pkgconfig-redundant.conf' >> "$portage/package.env/qt.conf"
                $cat << 'EOF' >> "$portage/package.use/vlc.conf"
dev-qt/qtgui -dbus
dev-qt/qtwidgets -gtk
sys-libs/zlib minizip
EOF
                ;;
        esac
}

# OPTIONAL (IMAGE)

function drop_debugging() {
        exclude_paths+=(
                usr/lib/.build-id
                usr/lib/debug
                usr/share/gdb
                usr/src
        )
}

function drop_development() {
        exclude_paths+=(
                etc/env.d/gcc
                etc/portage
                usr/include
                'usr/lib*/lib*.a'
                usr/lib/gcc
                usr/{'lib*',share}/pkgconfig
                usr/libexec/gcc
                usr/share/gcc-data
        )

        # Drop developer commands, then remove their dead links.
        rm -f root/usr/*bin/"${options[host]}"-*
        find root/usr/*bin -type l | while read
        do
                path=$(readlink "$REPLY")
                if [[ $path == /* ]]
                then test -e "root$path" || rm -f "$REPLY"
                else test -e "${REPLY%/*}/$path" || rm -f "$REPLY"
                fi
        done

        # Save required GCC shared libraries so /usr/lib/gcc can be dropped.
        mv -t root/usr/lib root/usr/lib/gcc/*/*/*.so*
}
