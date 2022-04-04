# SPDX-License-Identifier: GPL-3.0-or-later
packages=(app-shells/bash sys-apps/coreutils)
packages_buildroot=()

options[enforcing]=

function create_buildroot() {
        local -r arch=${options[arch]:=$DEFAULT_ARCH}
        local -r host=${options[host]:=$arch-${options[distro]}-linux-gnu$([[ $arch == arm* ]] && echo eabi${options[hardfp]:+hf})}
        local -r profile=${options[profile]-$(archmap_profile "$arch")}
        local -r stage3=${options[stage3]:-$(archmap_stage3)}

        opt bootable || opt selinux && packages_buildroot+=(sys-kernel/gentoo-sources)
        opt gpt && opt uefi && packages_buildroot+=(sys-fs/dosfstools sys-fs/mtools)
        opt ramdisk || opt selinux || opt verity_sig && packages_buildroot+=(app-arch/cpio)
        opt read_only && ! opt squash && packages_buildroot+=(sys-fs/erofs-utils)
        opt secureboot && packages_buildroot+=(app-crypt/pesign dev-libs/nss)
        opt selinux && packages_buildroot+=(app-emulation/qemu sys-apps/busybox)
        opt squash && packages_buildroot+=(sys-fs/squashfs-tools)
        opt uefi && packages_buildroot+=('<gnome-base/librsvg-2.41' media-gfx/imagemagick x11-themes/gentoo-artwork)
        opt verity && packages_buildroot+=(sys-fs/cryptsetup)
        packages_buildroot+=(dev-util/debugedit)

        $mkdir -p "$buildroot"
        $curl -L "$stage3.asc" > "$output/stage3.txz.sig"
        $curl -L "$stage3" > "$output/stage3.txz"
        verify_distro "$output"/stage3.txz{.sig,}
        $tar -C "$buildroot" -xJf "$output/stage3.txz"
        $rm -f "$output"/stage3.txz{.sig,}

        # Write a portage profile common to the native host and target system.
        local portage="$buildroot/etc/portage"
        $mv "$portage" "$portage.stage3"
        $mkdir -p "$portage"/{env,make.profile,package.{accept_keywords,env,license,mask,unmask,use},profile/{package.,}use.{force,mask},repos.conf}
        $cp -at "$portage" "$portage.stage3/make.conf"
        $cat << EOF >> "$portage/make.profile/parent"
gentoo:$(archmap_profile)
gentoo:targets/systemd$(
opt selinux && echo -e '\ngentoo:features/selinux')
EOF
        echo "$buildroot"/etc/env.d/gcc/config-* | $sed 's,.*/[^-]*-\(.*\),\nCBUILD="\1",' >> "$portage/make.conf"
        $cat << EOF >> "$portage/make.conf"
EMERGE_DEFAULT_OPTS="--jobs=$(c=(/sys/devices/system/cpu/cpu[0-9]*);for((n=${#c[@]}>>2,p=2;p<n;p<<=1))do :;done;echo $p)"
FEATURES="multilib-strict parallel-fetch parallel-install xattr -merge-sync -network-sandbox -news -selinux"
GRUB_PLATFORMS="${options[uefi]:+efi-$([[ $arch =~ 64 ]] && echo 64 || echo 32)}"
INPUT_DEVICES="libinput"
LLVM_TARGETS="$(archmap_llvm "$arch")"
POLICY_TYPES="${options[selinux]:-targeted}"
USE="\$USE system-icu system-png -fortran -gtk-doc -introspection -vala"
VIDEO_CARDS=""
EOF
        $cat << 'EOF' >> "$portage/package.accept_keywords/core.conf"
# Accept core utilities with no stable versions.
app-crypt/pesign ~*
sys-boot/vboot-utils ~*
sys-fs/erofs-utils ~*
EOF
        $cat << 'EOF' >> "$portage/package.accept_keywords/firefox.conf"
# Accept the latest (non-ESR) Firefox release.
dev-libs/nspr ~*
dev-libs/nss ~*
media-libs/dav1d ~*
www-client/firefox ~*
EOF
        $cat << 'EOF' >> "$portage/package.accept_keywords/gnome.conf"
# Accept viable versions of GNOME packages.
gnome-base/* *
gnome-extra/* *
app-arch/gnome-autoar *
dev-libs/libgweather *
gui-libs/libhandy *
media-gfx/gnome-screenshot *
media-libs/gsound *
net-libs/libnma *
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
        [[ $arch == aarch64 ]] && opt uefi && $cat << EOF >> "$portage/package.accept_keywords/arm64.conf"
# Accept binutils-2.38 to support AArch64 UEFI targets.
<sys-devel/binutils-2.39 **
<cross-$host/binutils-2.39 **
EOF
        $cat << 'EOF' >> "$portage/package.license/ucode.conf"
# Accept CPU microcode licenses.
sys-firmware/intel-microcode intel-ucode
sys-kernel/linux-firmware linux-fw-redistributable no-source-code
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
        $cat << 'EOF' >> "$portage/package.use/busybox.conf"
# Make busybox static by default since nobody expects it to be otherwise.
sys-apps/busybox static -pam
EOF
        $cat << 'EOF' >> "$portage/package.use/cdrtools.conf"
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
# Disable trying to build an initrd, and use hardened options.
sys-kernel/gentoo-kernel hardened -initramfs
# Apply patches to support more CPU optimizations, and link a default version.
sys-kernel/gentoo-sources experimental symlink
# Also link a default version when building release candidates.
sys-kernel/git-sources symlink
EOF
        $cat << 'EOF' >> "$portage/package.use/llvm.conf"
# Make clang use its own linker by default.
sys-devel/clang default-lld
EOF
        $cat << 'EOF' >> "$portage/package.use/selinux.conf"
# Don't pull in qt5 for SELinux tools.
app-admin/setools -X
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
        $cat << 'EOF' >> "$portage/profile/package.use.mask/emacs.conf"
# Support Emacs browser widgets everywhere so Emacs can handle everything.
app-editors/emacs -xwidgets
EOF
        $cat << 'EOF' >> "$portage/profile/package.use.mask/rust.conf"
# Allow sharing LLVM and the native Rust for cross-bootstrapping.
dev-lang/rust -system-bootstrap -system-llvm
EOF
        $cat << 'EOF' >> "$portage/profile/use.mask/ssl.conf"
# Mask support for insecure protocols.
sslv2
sslv3
EOF

        # Permit selectively toggling important features.
        echo -e '-selinux\n-static\n-static-libs' >> "$portage/profile/use.force/unforce.conf"
        echo -e '-clang\n-systemd' >> "$portage/profile/use.mask/unmask.conf"

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

        # Accept eselect-fontconfig-20220403 to fix symlinks.
        echo '<app-eselect/eselect-fontconfig-20220404 ~*' >> "$portage/package.accept_keywords/fontconfig.conf"
        # Accept eselect-iptables-20220320 to fix ip6tables.
        echo 'app-eselect/eselect-iptables *' >> "$portage/package.accept_keywords/iptables.conf"
        # Accept fontconfig-2.14 to fix the eselect module.
        echo '<media-libs/fontconfig-2.15 ~*' >> "$portage/package.accept_keywords/fontconfig.conf"
        # Accept polkit-0.120 to not require SpiderMonkey.
        echo '<sys-auth/polkit-0.121 ~*' >> "$portage/package.accept_keywords/polkit.conf"

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
        $cat << 'EOF' >> "$portage/package.use/gnutls.conf"
# When a package requires a single TLS implementation, standardize on GnuTLS.
net-misc/curl gnutls -curl_ssl_* curl_ssl_gnutls
net-misc/networkmanager gnutls -nss
EOF
        $cat << 'EOF' >> "$portage/package.use/kill.conf"
# Use the kill command from util-linux to minimize systemd dependencies.
sys-apps/util-linux kill
sys-process/procps -kill
EOF
        $cat << 'EOF' >> "$portage/package.use/nftables.conf"
# Use the newer backend in iptables.
net-firewall/iptables nftables
EOF
        $cat << 'EOF' >> "$portage/package.use/sqlite.conf"
# Always enable secure delete for SQLite.
dev-db/sqlite secure-delete
EOF
        echo 'EXTRA_EMAKE="GDBUS_CODEGEN=/usr/bin/gdbus-codegen GLIB_MKENUMS=/usr/bin/glib-mkenums"' >> "$portage/env/cross-emake-utils.conf"
        echo 'GLIB_COMPILE_RESOURCES="/usr/bin/glib-compile-resources"' >> "$portage/env/cross-glib-compile-resources.conf"
        echo 'GLIB_GENMARSHAL="/usr/bin/glib-genmarshal"' >> "$portage/env/cross-glib-genmarshal.conf"
        echo 'GLIB_MKENUMS="/usr/bin/glib-mkenums"' >> "$portage/env/cross-glib-mkenums.conf"
        echo 'EXTRA_ECONF="--with-libgmp-prefix=$SYSROOT/usr"' >> "$portage/env/cross-gmp.conf"
        echo 'LIBASSUAN_CONFIG="/usr/bin/$CHOST-pkg-config libassuan"' >> "$portage/env/cross-libassuan.conf"
        echo 'CFLAGS="$CFLAGS -I$SYSROOT/usr/include/libnl3"' >> "$portage/env/cross-libnl.conf"
        echo 'CPPFLAGS="$CPPFLAGS -I$SYSROOT/usr/include/libusb-1.0"' >> "$portage/env/cross-libusb.conf"
        echo 'EXTRA_EMAKE="PYTHON_INCLUDES=/usr/\$(host)/usr/include/\$\${PYTHON##*/}"' >> "$portage/env/cross-libxml2-python.conf"
        echo 'AT_M4DIR="m4"' >> "$portage/env/kbd.conf"
        echo "BUILD_PKG_CONFIG_LIBDIR=\"/usr/lib$([[ $DEFAULT_ARCH =~ 64 ]] && echo 64)/pkgconfig\"" >> "$portage/env/meson-pkgconfig.conf"
        echo 'EXTRA_ECONF="--with-sdkdir=/usr/include/xorg"' >> "$portage/env/xf86-sdk.conf"
        $cat << 'EOF' >> "$portage/package.env/fix-cross-compiling.conf"
# Adjust the environment for cross-compiling broken packages.
app-crypt/gnupg cross-libusb.conf
app-crypt/gpgme cross-libassuan.conf
app-i18n/ibus cross-glib-genmarshal.conf
dev-libs/dbus-glib cross-glib-genmarshal.conf
dev-libs/libxml2 cross-libxml2-python.conf
gnome-base/gnome-settings-daemon meson-pkgconfig.conf
gnome-base/librsvg cross-emake-utils.conf
net-libs/libmbim cross-emake-utils.conf
net-misc/modemmanager cross-emake-utils.conf
net-wireless/wpa_supplicant cross-libnl.conf
sys-apps/coreutils cross-gmp.conf
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
        echo '>=dev-lang/spidermonkey-91 -lto' >> "$portage/package.use/spidermonkey.conf"
        echo -e '-audit\n-caps' >> "$portage/profile/use.force/selinux.conf"
        echo split-usr >> "$portage/profile/use.mask/usrmerge.conf"

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
        # Mask the self-dependent NSS edit in the native root.
        echo 'dev-libs/nss::fixes' >> "$portage/package.mask/nss.conf"
        # Skip systemd for busybox since the labeling initrd has no real init.
        echo 'sys-apps/busybox -selinux -systemd' >> "$portage/package.use/busybox.conf"
        # Install colord utilities without the daemon due to huge dependencies.
        echo 'x11-misc/colord -daemon' >> "$portage/package.use/colord.conf"
        # Make a static libcrypt in the buildroot for busybox.
        echo -e 'sys-libs/libxcrypt static-libs\nvirtual/libcrypt static-libs' >> "$portage/package.use/libcrypt.conf"
        # Preserve JIT support in libpcre2 to avoid a needless rebuild.
        echo 'dev-libs/libpcre2 jit' >> "$portage/package.use/libpcre2.conf"
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

        # Write portage scripts for bootstrapping circular dependencies later.
        $cat << 'EOF' > "$buildroot/usr/bin/deepdeps"
#!/usr/bin/env python3
import portage, sys
def process(atom):
    matches = portage.portdb.match(atom)
    if len(matches) < 1: return
    settings.setcpv(portage.best(matches), mydb=portage.portdb)
    global deps
    if settings.mycpv in deps: return
    deps += [settings.mycpv]
    for dep in portage.dep.use_reduce(settings.get('DEPEND', '') + '\n' + settings.get('PDEPEND', '') + '\n' + settings.get('RDEPEND', ''), uselist=settings.get('PORTAGE_USE', '').split()):
        if type(dep) is not str or dep == '||' or dep.startswith('!'): continue
        process(dep.split('[')[0])
deps = []
settings = portage.config(clone=portage.settings)
for arg in sys.argv[1:]: process(arg)
for pkg in deps: print(pkg)
EOF
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
        $chmod 0755 "$buildroot"/usr/bin/{deepdeps,using}

        # Write cross-clang wrappers.  They'll fail if clang isn't installed.
        $cat << 'EOF' > "$buildroot/usr/bin/$host-clang"
#!/bin/sh -eu
name="${0##*/}"
host="${name%-*}"
prog="/usr/lib/llvm/13/bin/${name##*-}"
exec "$prog" --sysroot="/usr/$host" --target="$host" "$@"
EOF
        $chmod 0755 "$buildroot/usr/bin/$host-clang"
        $ln -fn "$buildroot/usr/bin/$host-clang"{,++}

        # Work around bad PolicyKit dependencies.
        $mkdir -p "$buildroot/usr/share/gettext/its"
        $ln -fst "$buildroot/usr/share/gettext/its" \
            "/usr/$host/usr/share/gettext/its"/polkit.{its,loc}

        write_base_kernel_config
        initialize_buildroot "$@"

        $cat <(declare -f write_overlay) - << 'EOF' | script "$host" "${packages_buildroot[@]}"
host=$1 ; shift
mkdir -p /run/lock  # Ensure this exists for bad packages.

# Fetch the latest package definitions, and fix them in an overlay.
emerge-webrsync
mkdir -p /var/db/repos/fixes/{eclass,metadata}
cat << 'EOG' > /var/db/repos/fixes/metadata/layout.conf
masters = gentoo
repo-name = fixes
EOG
tee {,/usr/"$host"}/etc/portage/repos.conf/fixes.conf << 'EOG'
[fixes]
location = /var/db/repos/fixes
EOG
write_overlay /var/db/repos/fixes
(cd /var/db/repos/gentoo/eclass ; exec ln -fst . ../../fixes/eclass/*)

# Update the native build root packages to the latest versions.
emerge --changed-use --deep --update --verbose --with-bdeps=y \
    @world sys-devel/crossdev

# Create the sysroot layout and cross-compiler toolchain.
export {PORTAGE_CONFIG,,SYS}ROOT="/usr/$host"
mkdir -p "$ROOT"/usr/{bin,src}
ln -fns bin "$ROOT/usr/sbin"
ln -fst "$ROOT" usr/{bin,sbin}
emerge --nodeps --oneshot --verbose sys-apps/baselayout
stable=$(portageq envvar ACCEPT_KEYWORDS | grep -Fqs -e '~' -e '**' || echo 1)
unset {PORTAGE_CONFIG,,SYS}ROOT
cat << 'EOG' >> /etc/portage/repos.conf/crossdev.conf
[crossdev]
location = /var/db/repos/crossdev
EOG
crossdev ${stable:+--stable} --target "$host"

# Install all requirements for building the target image.
exec emerge --changed-use --update --verbose "$@"
EOF

        build_relabel_kernel
}

function install_packages() {
        local -rx {PORTAGE_CONFIG,,SYS}ROOT="/usr/${options[host]}"
        local -a packages_sysroot=()

        opt bootable || opt networkd && packages+=(acct-group/mail sys-apps/systemd)
        opt selinux && packages+=(sec-policy/selinux-base-policy)

        # If a system-specific kernel config was not given, use dist-kernel.
        if opt bootable
        then
                test -s /etc/kernel/config.d/system.config &&
                : ${options[raw_kernel]=1}
                cat << EOF >> /etc/kernel/config.d/keys.config
CONFIG_MODULE_SIG_KEY="$keydir/sign.pem"
$(opt verity_sig || echo '#')CONFIG_SYSTEM_TRUSTED_KEYS="$keydir/verity.crt"
EOF
                if ! opt raw_kernel
                then
                        chgrp portage "$keydir" ; chmod g+x "$keydir"
                        packages_sysroot+=(sys-kernel/gentoo-kernel)
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
        mkdir -p /run/lock  # Ensure this exists for bad packages.
        COLLISION_IGNORE='*' USE=-selinux emerge --oneshot --verbose \
            sys-devel/gcc virtual/libc virtual/libcrypt virtual/os-headers
        packages+=(sys-devel/gcc virtual/libc)  # Install libstdc++ etc.

        # Cheat bootstrapping packages with circular dependencies.
        deepdeps "${packages[@]}" "${packages_sysroot[@]}" "$@" | sed 's/-[0-9].*//' > /root/xdeps
        USE='-* drm kill minimal nettle truetype' emerge --changed-use --oneshot --verbose \
            $(using media-libs/freetype harfbuzz && grep -Foxm1 media-libs/harfbuzz /root/xdeps) \
            $(using media-libs/libsndfile minimal || grep -Foxm1 media-libs/libsndfile /root/xdeps) \
            $(using media-libs/libwebp tiff && using media-libs/tiff webp && grep -Foxm1 media-libs/libwebp /root/xdeps) \
            $(using sys-fs/cryptsetup udev || using sys-fs/lvm2 udev && using sys-apps/systemd cryptsetup && grep -Foxm1 sys-fs/cryptsetup /root/xdeps) \
            $(using media-libs/mesa gallium vaapi && using x11-libs/libva opengl && grep -Foxm1 x11-libs/libva /root/xdeps) \
            sys-apps/util-linux

        # Cross-compile everything and make binary packages for the target.
        emerge --changed-use --deep --update --verbose --with-bdeps=y \
            "${packages[@]}" "${packages_sysroot[@]}" "$@"

        # Without GDB, assume debuginfo is unwanted to be like other distros.
        test -x "$ROOT/usr/bin/gdb" && : ${options[debuginfo]=1}
        opt debuginfo || local -rx INSTALL_MASK='/usr/lib/.build-id /usr/lib/debug /usr/share/gdb /usr/src'

        # Install the target root from binaries with no build dependencies.
        mkdir -p root/{dev,home,proc,srv,sys,usr/bin}
        mkdir -pm 0700 root/root
        ln -fns bin root/usr/sbin
        ln -fst root usr/{bin,sbin}
        ln -fns .. "root$ROOT"  # Lazily work around bad packaging.
        emerge --{,sys}root=root --jobs="$(nproc)" -1KOv sys-apps/baselayout
        emerge --{,sys}root=root --jobs="$(nproc)" -1Kv "${packages[@]}" "$@"
        mv -t root/usr/bin root/gcc-bin/*/* ; rm -fr root/{binutils,gcc}-bin

        # Create a UTF-8 locale so things work.
        localedef --prefix=root -c -f UTF-8 -i en_US en_US.UTF-8

        # If a modular unpackaged kernel was configured, install the modules.
        opt raw_kernel && grep -Fqsx CONFIG_MODULES=y /usr/src/linux/.config &&
        make -C /usr/src/linux modules_install \
            INSTALL_MOD_PATH=/wd/root \
            INSTALL_MOD_STRIP=$(opt debuginfo || echo 1) \
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

        test -s root/etc/bash/bashrc &&
        sed -i -e 's/PS1+=..[[]/&\\033[01;33m\\]$? \\[/;/\$ .$/s/PS1+=./&$? /' root/etc/bash/bashrc
        echo "alias ll='ls -l'" >> root/etc/skel/.bashrc

        # Add a mount point to support the ESP mount generator.
        opt uefi && mkdir -p root/boot

        # Create some usual stuff in /var that is missing.
        echo 'd /var/empty' > root/usr/lib/tmpfiles.d/var-compat.conf
        test -s root/usr/lib/sysusers.d/acct-user-polkitd.conf &&
        echo 'd /var/lib/polkit-1 - polkitd polkitd' >> root/usr/lib/tmpfiles.d/polkit.conf

        # Conditionalize wireless interfaces on their configuration files.
        test -s root/usr/lib/systemd/system/wpa_supplicant-nl80211@.service &&
        sed -i \
            -e '/^\[Unit]/aConditionFileNotEmpty=/etc/wpa_supplicant/wpa_supplicant-nl80211-%I.conf' \
            root/usr/lib/systemd/system/wpa_supplicant-nl80211@.service

        # The targeted policy does not support a sensitivity level.
        [[ ${options[selinux]:-targeted} == targeted ]] &&
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

        # Don't hijack key presses for searching in the web browser.
        compgen -G 'root/usr/lib*/firefox/browser/defaults/preferences/gentoo-prefs.js' &&
        sed -i -e /typeaheadfind/d root/usr/lib*/firefox/browser/defaults/preferences/gentoo-prefs.js

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
        test -s "$dir/pipewire-media-session.service" &&
        mkdir -p "$dir/pipewire.service.wants" &&
        ln -fst "$dir/pipewire.service.wants" ../pipewire-media-session.service

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

# Override ramdisk creation to drop microcode and support a builtin initramfs.
eval "$(declare -f squash | $sed \
    -e 's/build_microcode_ramdisk/:/' \
    -e 's/zstd --[^;]*/if opt monolithic ; then cat > /root/initramfs.cpio ; else & ; fi/')"

function save_boot_files() if opt bootable
then
        local -rx {PORTAGE_CONFIG,,SYS}ROOT="/usr/${options[host]}"
        opt uefi && USE=gnuefi emerge --buildpkg=n --changed-use --oneshot --verbose sys-apps/systemd
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
        create_ipe_policy
        local -r arch="$(archmap_kernel "${options[arch]}")"
        test -s vmlinux -o -s vmlinuz || if opt raw_kernel
        then
                if opt ipe || opt monolithic
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
                if opt ipe || opt monolithic
                then
                        chgrp portage /root ; chmod g+x /root
                        emerge --buildpkg=n --oneshot --verbose \
                            sys-kernel/gentoo-kernel
                        chgrp root /root ; chmod g-x /root
                fi
                local -r bd="$ROOT/usr/src/linux/arch/$arch/boot"
                test -s "$bd/Image.gz" && gzip -cd "$bd/Image.gz" > vmlinux ||
                cp -p "$bd"/*Image* vmlinuz
        fi < /dev/null
fi

# Override the UEFI function to support non-native stub files in Gentoo.
eval "$(declare -f produce_uefi_exe | $sed \
    -e 's/objcopy/"${options[host]}-&"/' \
    -e 's,/[^ ]*.efi.stub,/usr/${options[host]}&,')"

function create_ipe_policy() if opt ipe
then
        if opt monolithic
        then local -r initrd=/root/initramfs.cpio
        else local -r initrd=initrd.img
        fi

        # Make the default policy a whitelist based on enabled options.
        test -s ipe.policy || {
                cat << EOF
policy_name="default" policy_version=0.0.0
DEFAULT action=DENY
EOF
                if test -s "$initrd"
                then
                        echo op=EXECUTE boot_verified=TRUE action=ALLOW
                        echo op=KERNEL_READ boot_verified=TRUE action=ALLOW
                fi
                if opt verity_sig
                then
                        echo op=EXECUTE dmverity_signature=TRUE action=ALLOW
                        echo op=KERNEL_READ dmverity_signature=TRUE action=ALLOW
                elif opt verity
                then
                        local -r roothash=$(mapfile -d ' ' < dmsetup.txt && echo ${MAPFILE[11]})
                        echo op=EXECUTE dmverity_roothash="$roothash" action=ALLOW
                        echo op=KERNEL_READ dmverity_roothash="$roothash" action=ALLOW
                fi
        } > ipe.policy

        # Update the kernel configuration to include the policy.
        if opt raw_kernel
        then cat >> /usr/src/linux/.config
        else cat >> /etc/kernel/config.d/ipe.config
        fi << EOF
CONFIG_IPE_BOOT_POLICY="/wd/ipe.policy"
$(test -s "$initrd" || echo '#')CONFIG_IPE_PROP_BOOT_VERIFIED=y
EOF
fi

function build_busybox_initrd() if opt ramdisk || opt verity_sig
then
        local -r root=$(mktemp --directory --tmpdir="$PWD" ramdisk.XXXXXXXXXX)
        mkdir -p "$root"/{bin,dev,proc,sys,sysroot}

        # Cross-compile minimal static tools required for the initrd.
        local -rx {PORTAGE_CONFIG,,SYS}ROOT="/usr/${options[host]}"
        opt verity && USE=static-libs \
        emerge --buildpkg=n --changed-use --oneshot --verbose \
            dev-libs/libaio sys-apps/util-linux virtual/libcrypt
        USE='-* device-mapper-only static' \
        emerge --buildpkg=n --nodeps --oneshot --verbose \
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

        $mkdir -p "$patches/dev-lang/spidermonkey:78"
        $cat << 'EOF' > "$patches/dev-lang/spidermonkey:78/rust.patch"
--- a/build/moz.configure/rust.configure
+++ b/build/moz.configure/rust.configure
@@ -353,7 +353,7 @@
 
             return None
 
-        rustc_target = find_candidate(candidates)
+        rustc_target = os.getenv('RUST_TARGET') if host_or_target_str == 'target' and os.getenv('RUST_TARGET') is not None else find_candidate(candidates)
 
         if rustc_target is None:
             die("Don't know how to translate {} for rustc".format(
EOF

        if opt ipe
        then
                $mkdir -p "$patches"/sys-kernel/gentoo-{kernel,sources}
                $curl -L 'https://patchwork.kernel.org/series/562971/mbox' \
                    > "$patches/sys-kernel/gentoo-sources/ipe.patch"
                [[ $($sha256sum "$patches/sys-kernel/gentoo-sources/ipe.patch") == 81920cd54c22c19eed420b5ef349d68850562943d7b30a0aedc964346ad5261a\ * ]]
                $ln -fst "$patches/sys-kernel/gentoo-kernel" ../gentoo-sources/ipe.patch
        fi

        $mkdir -p "$patches"/{dev-lang/spidermonkey,www-client/firefox}
        $ln -fst "$patches/dev-lang/spidermonkey" ../../www-client/firefox/rust.patch
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
CONFIG_EXPERT=y
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
                opt ipe && { echo -n '# IPE settings
CONFIG_SECURITY=y
CONFIG_SECURITYFS=y
CONFIG_SECURITY_IPE=y
CONFIG_IPE_AUDIT_HASH_SHA512=y' ; opt ramdisk || opt verity_sig && echo -n '
CONFIG_IPE_PROP_BOOT_VERIFIED=y' ; opt verity && echo -n '
CONFIG_IPE_PROP_DM_VERITY_ROOTHASH=y' ; opt verity_sig && echo -n '
CONFIG_IPE_PROP_DM_VERITY_SIGNATURE=y' ; echo ; }
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
        echo > "$buildroot/root/config.relabel" 'CONFIG_EXPERT=y
# Target the native CPU.
'$([[ $DEFAULT_ARCH =~ 64 ]] || echo '#')'CONFIG_64BIT=y
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
        $gpg --import
        $gpg --verify "$1" "$2"
} << 'EOF'
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
Ua2+iy59K5kcdUTJlaQPq04JzjVMPbUl8vq+bJ4RTxVjMOx3Wh3BSzzxuLgfMQhK
6xtXbNOQeuRJa9iltLmuY0P8NeasPMXR8uFK5HkzXqQpSDCL/9GONLi/AxfM4ue/
vDLoq9q4qmPRqVcYn/uBYmaj5H5mGjmWtWXshLVVducKZIbCGymftthhbQBOXHpg
LVr3loU2J8Luwa1d1cCkudOZKas3p4gcxFPrzlBkzw5rb1YB+sc5jUhj8awJWY6S
6YrBIRwJufD6IUS++rIdbGHm/zn1yHNmYLtPcnbYHeErch+/NKoazH1HR152RxMf
BnvIbcqy0hXQ7TBeCS+K5fOKlYAwRXhWtEme+Hm0WXGh15DULYRzZf0SJKzrh+yt
nBykeXVaLsF04rkBDQRccTVSAQgAq68fEA7ThKy644fFN93foZ/3c0x4Ztjvozgc
/8U/xUIeDJLvd5FmeYC6b+Jx5DX1SAq4ZQHRI3A7NR5FSZU5x44+ai9VcOklegDC
Cm4QQeRWvhfE+OAB6rThOOKIEd01ICA4jBhxkPotC48kTPh2dP9eu7jRImDoODh7
DOPWDfOnfI5iSrAywFOGbYEe9h13LGyzWFBOCYNSyzG4z2yEazZNxsoDAILO22E+
CxDOf0j+iAKgxeb9CePDD7XwYNfuFpxhOU+oueH7LJ66OYAkmNXPpZrsPjgDZjQi
oigXeXCOGjg4lC1ER0HOrsxfwQNqqKxI+HqxBM2zCiDJUkH7FwARAQABiQPSBBgB
CgAmAhsCFiEEE+u9vt56Endd/bG6u1cuDi0YKRAFAlzEa/IFCQKLKU4BoMDUIAQZ
AQoAfRYhBFNOQgmrSe7hwZ2WFixEaV259gQ9BQJccTVSXxSAAAAAAC4AKGlzc3Vl
ci1mcHJAbm90YXRpb25zLm9wZW5wZ3AuZmlmdGhob3JzZW1hbi5uZXQ1MzRFNDIw
OUFCNDlFRUUxQzE5RDk2MTYyQzQ0Njk1REI5RjYwNDNEAAoJECxEaV259gQ9Lj8H
/36nBkey3W18e9LpOp8NSOtw+LHNuHlrmT0ThpmaZIjmn1G0VGLKzUljmrg/XLwh
E28ZHuYSwXIlBGMdTk1IfxWa9agnEtiVLa6cDiQqs3jFa6Qiobq/olkIzN8sP5kA
3NAYCUcmB/7dcw0s/FWUsyOSKseUWUEHQwffxZeI9trsuMTt50hm0xh8yy60jWPd
IzuY5V+C3M8YdP7oYS1l/9Oa0qf6nbmv+pKIq4D9zQuTUaCgL63Nyc7c2QrtY1cI
uNTxbGYMBrf/MOPnzxhh00cQh7SsrV2aUuMp+SV88H/onYw/iYiVEXDRgaLW8aZY
7qTAW3pS0sQ+nY5YDyo2gkIJELtXLg4tGCkQl84P/0yma5Y2F8pnSSoxXkQXzAo+
yYNM3qP62ESVCI+GU6pC95g6GAfskNqoKh/9HoJHrZZEwn6EETbAKPBiHcgpvqNA
FNZ+ceJqy3oJSW+odlsJoxltNJGxnxtAnwaGw/G+FB0y503EPcc+K4h9E0SUe6d3
BB9deoXIHxeCF1o5+5UWRJlMP8Q3sX1/yzvLrbQTN9xDh1QHcXKvbmbghT4bJgJC
4X6DZ013QkvN2E1j5+Nw74aMiG30EmXEvmC+gLYX8m7XEyjjgRqEdb1kWDo2x8D8
XohIZe4EG6d2hp3XI5i+9SnEksm79tkdv4n4uVK3MhjxbgacZrchsDBRVOrA7ZHO
z1CL5gmYDoaNQVXZvs1Fm2R3v4+VroeQizxAiYjL5PXJWVsVDTdKd5xJ32dLpY+J
nA51h79X4sJQMKjqloLHtkUgdEPlVtvh04GhiEKoC9vK7yDcOQgTiMPi7TEk2LT2
+Myv3lZXzv+FPw5hfSVWLuzoGKI56zhZvWujqJb1KHk+q9BToD/Xn855UsxKufWp
mOg4oAGM8oMFmpxBraNRmCMt+RqAt13KgvJFBi/sL91hNTrOkXwCZaVn9f67dXBV
MzgXmRQBLhHym4DcVwcfMaIK4NQqzVs6ZmZOKcPjv43aSZHRcaYaYOoWxXaqczL7
yqu4wb67pwMX312ABdpW
=kSzn
-----END PGP PUBLIC KEY BLOCK-----
EOF

function archmap() case ${*:-$DEFAULT_ARCH} in
    aarch64)  echo arm64 ;;
    arm*)     echo arm ;;
    i[3-6]86) echo x86 ;;
    powerpc*) echo ppc ;;
    riscv64)  echo riscv ;;
    x86_64)   echo amd64 ;;
    *) return 1 ;;
esac

function archmap_profile() {
        local -r hardened=/hardened
        local -r nomulti=$(opt multilib || echo /no-multilib)
        case ${*:-$DEFAULT_ARCH} in
            aarch64)     echo default/linux/arm64/17.0$hardened ;;
            armv4t*)     echo default/linux/arm/17.0/armv4t ;;
            armv5te*)    echo default/linux/arm/17.0/armv5te ;;
            armv6*j*)    echo default/linux/arm/17.0/armv6j$hardened ;;
            armv7a)      echo default/linux/arm/17.0/armv7a$hardened ;;
            i[3-6]86)    echo default/linux/x86/17.0$hardened ;;
            powerpc)     echo default/linux/ppc/17.0 ;;
            powerpc64le) echo default/linux/ppc64le/17.0 ;;
            riscv64)     echo default/linux/riscv/20.0/rv64gc/lp64d ;;
            x86_64)      echo default/linux/amd64/17.1$nomulti$hardened ;;
            *) return 1 ;;
        esac
}

function archmap_stage3() {
        local -r base="https://gentoo.osuosl.org/releases/$(archmap "$@")/autobuilds"
        local -r hardened=-hardened
        local -r hardfp=${options[hardfp]:+_hardfp}
        local -r nomulti=$(opt multilib || echo -nomultilib)
        local -r selinux=${options[selinux]:+-selinux}

        local stage3
        case ${*:-$DEFAULT_ARCH} in
            aarch64)     stage3=stage3-arm64-systemd ;;
            armv4tl)     stage3=stage3-armv4tl-systemd ;;
            armv5tel)    stage3=stage3-armv5tel-systemd ;;
            armv6*j*)    stage3=stage3-armv6j$hardfp-systemd ;;
            armv7a)      stage3=stage3-armv7a$hardfp-systemd ;;
            i[45]86)     stage3=stage3-i486-openrc ;;
            i686)        stage3=stage3-i686$hardened-openrc ;;
            powerpc)     stage3=stage3-ppc-openrc ;;
            powerpc64le) stage3=stage3-ppc64le-systemd ;;
            x86_64)      stage3=stage3-amd64$hardened$nomulti$selinux-openrc ;;
            *) return 1 ;;
        esac

        local -r build=$($curl -L "$base/latest-$stage3.txt" | $sed -n '/^[0-9]\{8\}T[0-9]\{6\}Z/{s/Z.*/Z/p;q;}')
        echo "$base/$build/$stage3-$build.tar.xz"
}

function write_overlay() {
        local -r gentoo=/var/db/repos/gentoo
        local -r overlay=$1

        function edit() {
                local file from="$gentoo/$1" to="$overlay/$1" ; shift
                mkdir -p "$to"
                cp -pt "$to" "$from/metadata.xml"
                [[ -d $from/files ]] && cp -at "$to" "$from/files"
                sed /^EBUILD/d "$from/Manifest" > "$to/Manifest"
                for file in "$from"/*.ebuild
                do sed "$@" "$file" > "$to/${file##*/}"
                done
                ebuild "$to/${file##*/}" manifest
        }

        # Support cross-compiling with LLVM (#745744).
        sed -e '/llvm_path=/s/x "/x $([[ $EAPI == 6 ]] || echo -b) "/' \
            "$gentoo/eclass/llvm.eclass" > "$overlay/eclass/llvm.eclass"

        # Support autotools with EAPI 8.
        sed -e 's/7)$/*)/' \
            "$gentoo/eclass/autotools.eclass" > "$overlay/eclass/autotools.eclass"

        # Support tmpfiles with EAPI 8.
        sed -e 's/R\(DEPEND=.*\)/[[ ${EAPI} -lt 8 ]] \&\& & || I\1/' \
            "$gentoo/eclass/tmpfiles.eclass" > "$overlay/eclass/tmpfiles.eclass"

        # Support installing the distro kernel without /usr/src.
        sed -e '/^kernel-install_pkg_preinst/a[[ ${MERGE_TYPE} == binary ]] && return' \
            "$gentoo/eclass/kernel-install.eclass" > "$overlay/eclass/kernel-install.eclass"

        # Support building kernel modules in a sysroot.
        sed -e 's,\(KERNEL_DIR:=\)\(/usr/src\),\1${ROOT%/}\2,' \
            "$gentoo/eclass/linux-mod.eclass" > "$overlay/eclass/linux-mod.eclass"

        # Support compiling basic qt5 packages in a sysroot.
        sed \
            -e '/conf=/a${SYSROOT:+-extprefix "${QT5_PREFIX}" -sysroot "${SYSROOT}"}' \
            -e 's/ OBJDUMP /&PKG_CONFIG /;/OBJCOPY/{p;s/OBJCOPY/PKG_CONFIG/g;}' \
            "$gentoo/eclass/qt5-build.eclass" > "$overlay/eclass/qt5-build.eclass"
        edit dev-qt/qtgui '/^DEPEND=/iBDEPEND="~dev-qt/qtcore-${PV}"'
        edit dev-qt/qtwidgets '/^DEPEND=/iBDEPEND="~dev-qt/qtgui-${PV}"'
        edit dev-qt/qtsvg '/^DEPEND=/iBDEPEND="~dev-qt/qtwidgets-${PV}"'
        edit dev-qt/qtx11extras '/^DEPEND=/iBDEPEND="~dev-qt/qtwidgets-${PV}"'

        # Drop the buildroot multilib requirement for Rust (#753764).
        edit gnome-base/librsvg 's/^EAPI=.*/EAPI=7/;s,^DEPEND=.*[^"]$,&"\nBDEPEND="x11-libs/gdk-pixbuf,;/rust/s/[[].*MULTI.*]//;/^src_prepare/a\
export CARGO_HOME=$T ; [[ -z ${RUST_TARGET-} ]] || echo -e "[target.$RUST_TARGET]\nlinker = \\"$CHOST-gcc\\"" > "$CARGO_HOME/config.toml"'

        # Fix sestatus installation with UsrMerge (or unified bindir, really).
        edit sys-apps/policycoreutils '/setfiles/ause split-usr || rm -f "${ED}/usr/sbin/sestatus"'

        # Fix the libcap dependency.
        edit sys-libs/pam 's/^EAPI=.*/EAPI=8/'

        # Fix tmpfiles dependencies.
        edit sys-fs/cryptsetup 's/^EAPI=.*/EAPI=8/'
        edit sys-fs/lvm2 's/^EAPI=.*/EAPI=8/;/TMPFILES_OPTIONAL\|virtual.tmpfiles/d'

        # Fix NSS self-dependency.
        edit dev-libs/nss 's,^BDEPEND=",&dev-libs/nss ,;/^EAPI="*[^"67]/aIDEPEND="dev-libs/nss"'

        # Fix udev dependency ordering.
        edit sys-libs/libblockdev /sys-block.parted/avirtual/libudev

        # Fix NetworkManager configuration.
        edit net-misc/networkmanager '/docs/s/true/use_bool introspection/'

        # Fix colord self-dependency.
        edit x11-misc/colord 's/^IUSE="/&+daemon /;s/.*polkit.*/daemon? ( & )/;s,^BDEPEND=",&daemon? ( ${CATEGORY}/${PN} ) ,;s/true daemon/use_bool daemon/;/^src_prepare/a\
use daemon && sed -i -e "s,cd_idt8,'\''/usr/bin/cd-it8'\'',;s,cd_create_profile,'\''/usr/bin/cd-create-profile'\''," data/*/meson.build'

        # Remove eselect from the sysroot.
        edit app-crypt/pinentry 's/^EAPI=.*/EAPI=8/;/app-eselect/{x;d;};${s/$/\nIDEPEND="/;G;s/$/"/;}'
        edit app-editors/emacs 's/.{IDEPEND}//'
        edit dev-libs/libcdio-paranoia 's/^EAPI=.*/EAPI=8/;/^RDEPEND=.*eselect/{s/^R/I/;s/$/"\nRDEPEND="/;}'
        edit net-firewall/iptables 's/^EAPI=.*/EAPI=8/;/app-eselect/d;$aIDEPEND="app-eselect/eselect-iptables"'
}

# OPTIONAL (BUILDROOT)

function fix_package() {
        local -r portage="$buildroot/usr/${options[host]}/etc/portage"
        case $* in
            vlc)
                [[ ${options[arch]} =~ 64 ]] &&
                echo 'PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib64/pkgconfig:$SYSROOT/usr/share/pkgconfig"' >> "$portage/env/pkgconfig-redundant.conf" ||
                echo 'PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"' >> "$portage/env/pkgconfig-redundant.conf"
                echo 'dev-qt/* pkgconfig-redundant.conf' >> "$portage/package.env/qt.conf"
                $cat << 'EOF' >> "$portage/package.use/vlc.conf"
dev-qt/qtgui -dbus
dev-qt/qtwidgets -dbus -gtk
sys-libs/zlib minizip
EOF
                ;;
        esac
}

# OPTIONAL (IMAGE)

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
        rm -f root/usr/bin/"${options[host]}"-*
        find root/usr/bin -type l | while read
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
