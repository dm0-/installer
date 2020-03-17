packages=()
packages_buildroot=()

function create_buildroot() {
        local -r arch=${options[arch]:=$DEFAULT_ARCH}
        local -r profile=${options[profile]:-$(archmap_profile "$arch")}
        local -r stage3=${options[stage3]:-$(archmap_stage3)}
        local -r host=${options[host]:=$arch-${options[distro]}-linux-gnu$([[ $arch == arm* ]] && echo eabi)$([[ $arch == armv7* ]] && echo hf)}

        opt bootable || opt selinux && packages_buildroot+=(sys-kernel/gentoo-sources)
        opt executable && opt uefi && packages_buildroot+=(sys-fs/dosfstools sys-fs/mtools)
        opt ramdisk || opt selinux && packages_buildroot+=(app-arch/cpio)
        opt read_only && ! opt squash && packages_buildroot+=(sys-fs/erofs-utils)
        opt selinux && packages_buildroot+=(app-emulation/qemu)
        opt squash && packages_buildroot+=(sys-fs/squashfs-tools)
        opt verity && packages_buildroot+=(sys-fs/cryptsetup)
        opt uefi && packages_buildroot+=(media-gfx/imagemagick x11-themes/gentoo-artwork) &&
        opt sb_cert && opt sb_key && packages_buildroot+=(app-crypt/pesign dev-libs/nss)

        $mkdir -p "$buildroot"
        $curl -L "$stage3.DIGESTS.asc" > "$output/digests"
        $curl -L "$stage3" > "$output/stage3.tar.xz"
        verify_distro "$output/digests" "$output/stage3.tar.xz"
        $tar -C "$buildroot" -xJf "$output/stage3.tar.xz"
        $rm -f "$output/digests" "$output/stage3.tar.xz"

        # Write a portage profile common to the native host and target system.
        local portage="$buildroot/etc/portage"
        $ln -fns "../../var/db/repos/gentoo/profiles/$(archmap_profile)" "$portage/make.profile"
        $mkdir -p "$portage"/{env,package.{accept_keywords,env,license,mask,unmask,use},profile,repos.conf}
        echo "$buildroot"/etc/env.d/gcc/config-* | $sed 's,.*/[^-]*-\(.*\),\nCBUILD="\1",' >> "$portage/make.conf"
        $cat << EOF >> "$portage/make.conf"
FEATURES="\$FEATURES multilib-strict parallel-fetch parallel-install xattr -network-sandbox -news -selinux"
GRUB_PLATFORMS="${options[uefi]:+efi-64}"
INPUT_DEVICES="libinput"
LLVM_TARGETS="$(archmap_llvm "$arch")"
POLICY_TYPES="targeted"
USE="\$USE${options[selinux]:+ selinux} system-llvm systemd"
VIDEO_CARDS=""
EOF
        $cat << 'EOF' >> "$portage/package.accept_keywords/boot.conf"
# Accept boot-related utilities with no stable versions.
app-crypt/pesign
sys-boot/vboot-utils
EOF
        $cat << 'EOF' >> "$portage/package.accept_keywords/linux.conf"
# Accept the newest kernel and SELinux policy.
sys-kernel/gentoo-sources
sys-kernel/linux-headers
sec-policy/*
EOF
        $cat << 'EOF' >> "$portage/package.license/ucode.conf"
# Accept CPU microcode licenses.
sys-firmware/intel-microcode intel-ucode
sys-kernel/linux-firmware linux-fw-redistributable no-source-code
EOF
        $cat << 'EOF' >> "$portage/package.unmask/systemd.conf"
# Unmask systemd when SELinux is enabled.
gnome-base/*
gnome-extra/*
sys-apps/gentoo-systemd-integration
sys-apps/systemd
EOF
        $cat << 'EOF' >> "$portage/package.use/cryptsetup.conf"
# Choose nettle as the crypto backend and LUKS2 as the default LUKS version.
sys-fs/cryptsetup nettle -gcrypt -kernel -luks1_default -openssl
# Skip LVM by default so it doesn't get installed for cryptsetup/veritysetup.
sys-fs/lvm2 device-mapper-only -thin
EOF
        $cat << 'EOF' >> "$portage/package.use/kmod.conf"
# Support installing kernels configured with compressed modules.
sys-apps/kmod lzma
EOF
        $cat << 'EOF' >> "$portage/package.use/policycoreutils.conf"
# Block bad dependencies for restorecond, which is pretty useless these days.
sys-apps/policycoreutils -dbus
EOF
        $cat << 'EOF' >> "$portage/package.use/squashfs-tools.conf"
# Support zstd squashfs compression.
sys-fs/squashfs-tools zstd
EOF
        $cat << 'EOF' >> "$portage/profile/package.provided"
# These Python tools are not useful, and they pull in horrific dependencies.
app-admin/setools-9999
EOF
        $cat << 'EOF' >> "$portage/profile/packages"
# Don't force building HFS utilities.
-*sys-fs/hfsutils
-*sys-fs/hfsplusutils
EOF
        $cat << 'EOF' >> "$portage/profile/use.mask"
# Mask support for insecure protocols.
sslv2
sslv3
EOF

        # Permit selectively toggling important features.
        echo -e '-selinux\n-static\n-static-libs' >> "$portage/profile/use.force"
        echo -e '-cet\n-system-llvm\n-systemd' >> "$portage/profile/use.mask"

        # Write build environment modifiers for later use.
        echo "CTARGET=\"$host\"" >> "$portage/env/ctarget.conf"
        echo 'LDFLAGS="-lgcc_s $LDFLAGS"' >> "$portage/env/link-gcc_s.conf"
        $cat << 'EOF' >> "$portage/env/no-lto.conf"
CFLAGS="$CFLAGS -fno-lto"
CXXFLAGS="$CXXFLAGS -fno-lto"
FFLAGS="$FFLAGS -fno-lto"
FCFLAGS="$FCFLAGS -fno-lto"
EOF

        # Accept binutils-2.34 to fix host dependencies.
        echo -e '<sys-devel/binutils-2.35\n<sys-libs/binutils-libs-2.35' >> "$portage/package.accept_keywords/binutils.conf"
        # Accept ffmpeg-4.2 to fix host dependencies.
        echo '<media-video/ffmpeg-4.3' >> "$portage/package.accept_keywords/ffmpeg.conf"
        # Accept grub-2.06 to fix file modification time support on ESPs.
        echo '<sys-boot/grub-2.07' >> "$portage/package.accept_keywords/grub.conf"
        # Accept iptables-1.8 to fix missing flags.
        echo net-firewall/iptables >> "$portage/package.accept_keywords/iptables.conf"
        # Accept libcap-2.33 to fix build ordering with EAPI=7.
        echo '<sys-libs/libcap-2.34' >> "$portage/package.accept_keywords/libcap.conf"
        # Accept libxcb-1.14 to fix root dependencies with EAPI=7.
        echo -e 'x11-base/xcb-proto\nx11-libs/libxcb' >> "$portage/package.accept_keywords/xcb.conf"
        # Accept pango-1.44.7 to fix host dependencies.
        echo x11-libs/pango >> "$portage/package.accept_keywords/pango.conf"
        echo x11-libs/pango >> "$portage/package.unmask/pango.conf"
        # Accept systemd-245 to fix sysusers for GLEP 81.
        echo '<sys-apps/systemd-246' >> "$portage/package.accept_keywords/systemd.conf"
        # Accept upower-0.99.11 to fix SELinux labels on state directories.
        echo '~sys-power/upower-0.99.11' >> "$portage/package.accept_keywords/upower.conf"
        # Accept util-linux-2.34 to fix build ordering with EAPI=7.
        echo '<sys-apps/util-linux-2.35' >> "$portage/package.accept_keywords/util-linux.conf"

        # Create the target portage profile based on the native root's.
        portage="$buildroot/usr/$host/etc/portage"
        $mkdir -p "${portage%/portage}"
        $cp -at "${portage%/portage}" "$buildroot/etc/portage"
        $ln -fns "../../../../var/db/repos/gentoo/profiles/$profile" "$portage/make.profile"
        $sed -i -e '/^COMMON_FLAGS=/s/[" ]*$/ -g -flto=jobserver&/' "$portage/make.conf"
        $cat <(echo -e "\nCHOST=\"$host\"") - << 'EOF' >> "$portage/make.conf"
ROOT="/usr/$CHOST"
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
        $cat << 'EOF' >> "$portage/package.use/portage.conf"
# Cross-compiling portage native extensions is unsupported.
sys-apps/portage -native-extensions
EOF
        echo 'EXTRA_ECONF="--with-dbus-binding-tool=dbus-binding-tool"' >> "$portage/env/cross-dbus-glib.conf"
        echo 'GLIB_COMPILE_RESOURCES="/usr/bin/glib-compile-resources"' >> "$portage/env/cross-glib.conf"
        echo 'CPPFLAGS="$CPPFLAGS -I$SYSROOT/usr/include/libusb-1.0"' >> "$portage/env/cross-libusb.conf"
        echo 'PKG_CONFIG="$CHOST-pkg-config"' >> "$portage/env/cross-pkgconfig.conf"
        echo 'CPPFLAGS="$CPPFLAGS -I$SYSROOT/usr/include/python3.6m"' >> "$portage/env/cross-python.conf"
        echo 'EXTRA_ECONF="--with-incs-from= --with-libs-from="' >> "$portage/env/cross-windowmaker.conf"
        $cat << 'EOF' >> "$portage/package.env/fix-cross-compiling.conf"
# Adjust the environment for cross-compiling broken packages.
app-crypt/gnupg cross-libusb.conf
dev-libs/dbus-glib cross-dbus-glib.conf
dev-python/pypax cross-python.conf
sys-apps/dtc cross-pkgconfig.conf
x11-libs/gtk+ cross-glib.conf
x11-wm/windowmaker cross-windowmaker.conf
EOF
        $cat << 'EOF' >> "$portage/package.env/no-lto.conf"
# Turn off LTO for broken packages.
dev-libs/elfutils no-lto.conf
dev-libs/icu no-lto.conf
dev-libs/libaio no-lto.conf
media-libs/alsa-lib no-lto.conf
media-sound/pulseaudio no-lto.conf
net-libs/webkit-gtk no-lto.conf
sys-fs/fuse no-lto.conf
sys-libs/libselinux no-lto.conf
sys-libs/libsemanage no-lto.conf
sys-libs/libsepol no-lto.conf
EOF
        $cat << 'EOF' >> "$portage/profile/package.provided"
# The kernel source is shared between the host and cross-compiled root.
sys-kernel/gentoo-sources-9999
EOF
        echo split-usr >> "$portage/profile/use.mask"

        # Write portage profile settings that only apply to the native root.
        portage="$buildroot/etc/portage"
        # Compile GRUB modules for the target system.
        echo 'sys-boot/grub ctarget.conf' >> "$portage/package.env/grub.conf"
        # Link a required library for building the SELinux labeling initrd.
        echo 'sys-fs/squashfs-tools link-gcc_s.conf' >> "$portage/package.env/squashfs-tools.conf"
        # Turn off extra busybox features to make the labeling initrd smaller.
        echo 'sys-apps/busybox -* static' >> "$portage/package.use/busybox.conf"
        # Work around bad dependencies requiring this on the host.
        echo 'x11-libs/cairo X' >> "$portage/package.use/cairo.conf"
        echo 'media-libs/libglvnd X' >> "$portage/package.use/libglvnd.conf"
        # Support building the UEFI boot stub, its logo image, and signing tools.
        opt uefi && $cat << 'EOF' >> "$portage/package.use/uefi.conf"
dev-libs/nss utils
media-gfx/imagemagick svg xml
sys-apps/pciutils -udev
sys-apps/systemd gnuefi
EOF

        initialize_buildroot

        script "$host" "${packages_buildroot[@]}" "$@" << 'EOF'
host=$1 ; shift

# Fetch the latest package definitions, and fix them.
emerge-webrsync
## Support sysusers (#702624).
curl -L 'https://bugs.gentoo.org/attachment.cgi?id=599352' > sysusers.patch
test x$(sha256sum sysusers.patch | sed -n '1s/ .*//p') = xf749a2e2221b31613cdd28f1144cf8656457b663a7603bc82c59aa181bbcc917
sed -i -e 's/.*USER_ID.*}/&:${ACCT_USER_GROUPS[0]}/;s/printf "m/test ${#ACCT_USER_GROUPS[*]} -lt 2 || &/;s/.*GROUPS.@]/&:1/' sysusers.patch
patch -d /var/db/repos/gentoo -p1 < sysusers.patch ; rm -f sysusers.patch
## Support cross-compiling hyphen without rebuilding Perl (#708258).
sed -i -e 's/^DEPEND=".*/&"\nBDEPEND="/' /var/db/repos/gentoo/dev-libs/hyphen/hyphen-2.8.8-r1.ebuild
ebuild /var/db/repos/gentoo/dev-libs/hyphen/hyphen-2.8.8-r1.ebuild manifest
## Support erofs-utils (#701284).
if test "x$*" != "x${*/erofs-utils}"
then
        mkdir -p /var/cache/distfiles /var/db/repos/gentoo/sys-fs/erofs-utils
        curl -L 'https://bugs.gentoo.org/attachment.cgi?id=597574' > /var/db/repos/gentoo/sys-fs/erofs-utils/erofs-utils-1.0.ebuild
        test x$(sha256sum /var/db/repos/gentoo/sys-fs/erofs-utils/erofs-utils-1.0.ebuild | sed -n '1s/ .*//p') = x81dec7d30505c1dae482fe2bb067b3dcf6d11ad792f3fc0cb791d1e4c03eff44
        curl -L 'https://git.kernel.org/pub/scm/linux/kernel/git/xiang/erofs-utils.git/snapshot/erofs-utils-1.0.tar.gz' > /var/cache/distfiles/erofs-utils-1.0.tar.gz
        test x$(sha256sum /var/cache/distfiles/erofs-utils-1.0.tar.gz | sed -n '1s/ .*//p') = x508ee818dc6a02cf986647e37cb991b76f7b3e7ea303ffc9e980772de68f3b10
        ebuild /var/db/repos/gentoo/sys-fs/erofs-utils/erofs-utils-1.0.ebuild manifest --force
fi

# Update the native build root packages to the latest versions.
emerge --changed-use --deep --jobs=4 --update --verbose --with-bdeps=y \
    @world dev-util/debugedit sys-devel/crossdev

# Create the cross-compiler toolchain in the native build root.
cat << 'EOG' >> /etc/portage/repos.conf/crossdev.conf
[crossdev]
location = /var/db/repos/crossdev
EOG
mkdir -p /usr/"$host"/usr/{bin,lib,lib64,sbin,src}
ln -fst "/usr/$host" usr/{bin,lib,lib64,sbin}
crossdev --stable --target "$host"

# Install all requirements for building the target image.
emerge --changed-use --jobs=4 --update --verbose "$@"

# Share the clean kernel source between roots if it's installed.
if test -d /usr/src/linux
then
        ln -fst "/usr/$host/usr/src" ../../../../usr/src/linux
        make -C /usr/src/linux -j$(nproc) mrproper V=1
fi
EOF

        build_relabel_kernel
        write_base_kernel_config
}

function install_packages() {
        local -rx {PORTAGE_CONFIG,,SYS}ROOT="/usr/${options[host]}"

        opt bootable || opt networkd && packages+=(acct-group/mail sys-apps/systemd)
        opt selinux && packages+=(sec-policy/selinux-base-policy)
        packages+=(sys-apps/baselayout)

        # Build the final kernel.
        if opt bootable
        then
                local -r kernel_arch="$(archmap_kernel "${options[arch]}")"
                test -s /usr/src/linux/.config
                opt sb_key && sed -i -e "/^CONFIG_MODULE_SIG_KEY=.certs.signing_key.pem.$/s,=\".*,=\"$keydir/sign.pem\"," /usr/src/linux/.config
                make -C /usr/src/linux -j$(nproc) V=1 \
                    ARCH="$kernel_arch" CROSS_COMPILE="${options[host]}-"
                make -C /usr/src/linux install V=1 \
                    ARCH="$kernel_arch" CROSS_COMPILE="${options[host]}-"
        fi < /dev/null

        # Build the cross-compiled toolchain packages first.
        COLLISION_IGNORE='*' USE=-selinux emerge --jobs=4 --verbose \
            sys-devel/gcc sys-kernel/linux-headers sys-libs/glibc
        packages+=(sys-devel/gcc sys-libs/glibc)  # Install libstdc++ etc.

        # These packages must be installed outside the dependency graph.
        emerge --jobs=4 --nodeps --verbose \
            media-fonts/font-util \
            ${options[selinux]:+sec-policy/selinux-base} \
            x11-base/x{cb,org}-proto

        # Cheat systemd bootstrapping.
        USE='-* kill' emerge --jobs=4 --verbose sys-apps/util-linux

        # Cross-compile everything and make binary packages for the target.
        emerge --changed-use --deep --jobs=4 --update --verbose --with-bdeps=y \
            @world "${packages[@]}" "$@"

        # Install the target root from binaries with no build dependencies.
        mkdir -p root/{dev,etc,home,proc,run,srv,sys,usr/{bin,lib,sbin}}
        mkdir -pm 0700 root/root
        [[ ${options[arch]-} =~ 64 ]] && ln -fns lib root/usr/lib64
        (cd root ; exec ln -fst . usr/*)
        ln -fns .. "root$ROOT"  # Lazily work around bad packaging.
        emerge --{,sys}root=root --jobs=$(nproc) -1Kv "${packages[@]}" "$@"
        mv -t root/usr/bin root/gcc-bin/*/* ; rm -fr root/{binutils,gcc}-bin

        # If a modular kernel was configured, install the stripped modules.
        opt bootable && grep -Fqsx CONFIG_MODULES=y /usr/src/linux/.config &&
        make -C /usr/src/linux modules_install V=1 \
            INSTALL_MOD_PATH=/wd/root INSTALL_MOD_STRIP=1 \
            ARCH="$kernel_arch" CROSS_COMPILE="${options[host]}-"

        # List everything installed in the image and what was used to build it.
        qlist -CIRSSUv > packages-buildroot.txt
        qlist --root=/ -CIRSSUv > packages-host.txt
        qlist --root=root -CIRSSUv > packages.txt

        # Cross-compile minimal tools for an initrd after everything is done.
        if opt ramdisk
        then
                opt verity && USE=static-libs \
                emerge --buildpkg=n --changed-use --jobs=4 --oneshot --verbose \
                    dev-libs/libaio sys-apps/util-linux
                USE='-* device-mapper-only static' \
                emerge --buildpkg=n --jobs=4 --nodeps --oneshot --verbose \
                    sys-apps/busybox ${options[verity]:+sys-fs/lvm2}
        fi
}

function distro_tweaks() {
        ln -fns ../lib/systemd/systemd root/usr/sbin/init
        ln -fns ../proc/self/mounts root/etc/mtab

        sed -i -e 's/PS1+=..[[]/&\\033[01;33m\\]$? \\[/;/\$ .$/s/PS1+=./&$? /' root/etc/bash/bashrc
        echo "alias ll='ls -l'" >> root/etc/skel/.bashrc

        # Add a mount point to support the ESP mount generator.
        opt uefi && mkdir root/boot

        # Create some usual stuff in /var that is missing.
        cat << 'EOF' > root/usr/lib/tmpfiles.d/var-compat.conf
d /var/empty
L /var/lock - - - - ../run/lock
EOF

        # Conditionalize wireless interfaces on their configuration files.
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

        # Link BIOS files where QEMU expects to find them.
        test -d root/usr/share/qemu -a -d root/usr/share/seavgabios &&
        (cd root/usr/share/qemu ; exec ln -fst . ../sea{,vga}bios/*)

        # Set some sensible key behaviors for a bare X session.
        test -x root/usr/bin/startx &&
        mkdir -p  root/etc/X11/xorg.conf.d &&
        cat << 'EOF' > root/etc/X11/xorg.conf.d/00-keyboard.conf
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbOptions" "ctrl:nocaps"
EndSection
EOF

        # Select a default desktop environment for startx, or default to twm.
        test -s root/etc/X11/Sessions/wmaker &&
        echo XSESSION=wmaker > root/etc/env.d/90xsession

        # Magenta looks more "Gentoo" than green, as in the website and logo.
        sed -i -e '/^ANSI_COLOR=/s/32/35/' root/etc/os-release
}

function save_boot_files() if opt bootable
then
        test -s vmlinux || cp -p /boot/vmlinux-* vmlinux ||
        test -s vmlinuz || cp -p /boot/vmlinuz-* vmlinuz
        opt uefi && test ! -s logo.bmp &&
        sed -i -e '/namedview/,/<.g>/d' /usr/share/pixmaps/gentoo/misc/svg/GentooWallpaper_2.svg &&
        magick -background none /usr/share/pixmaps/gentoo/misc/svg/GentooWallpaper_2.svg -trim -color-matrix '0 1 0 0 0 0 0 1 0 0 0 0 0 0 1 0 0 0 1 0 1 0 0 0 0' logo.bmp
        test -s os-release || cp -pt . root/etc/os-release
fi

function build_ramdisk() if opt ramdisk
then
        local -r sysroot="/usr/${options[host]}"
        local -r root=$(mktemp --directory --tmpdir="$PWD" ramdisk.XXXXXXXXXX)
        mkdir -p "$root"/{bin,dev,proc,sys,sysroot}
        cp -pt "$root/bin" "$sysroot/bin/busybox"
        for cmd in ash mount losetup switch_root
        do ln -fns busybox "$root/bin/$cmd"
        done
        opt verity && cp -p "$sysroot/sbin/dmsetup.static" "$root/bin/dmsetup"
        cat << EOF > "$root/init" && chmod 0755 "$root/init"
#!/bin/ash -eux
export PATH=/bin
mount -nt devtmpfs devtmpfs /dev
mount -nt proc proc /proc
mount -nt sysfs sysfs /sys
losetup ${options[read_only]:+-r }/dev/loop0 /sysroot/root.img
$(opt verity && cat << EOG ||
dmsetup create --concise '$(<dmsetup.txt)'
mount -no ro /dev/mapper/root /sysroot
EOG
echo "mount -n${options[read_only]:+o ro} /dev/loop0 /sysroot")
exec switch_root /sysroot /sbin/init
EOF
        ln -fn final.img "$root/sysroot/root.img"
        find "$root" -mindepth 1 -printf '%P\n' |
        cpio -D "$root" -H newc -R 0:0 -o |
        xz --check=crc32 -9e > ramdisk.img
fi

function write_base_kernel_config() if opt bootable
then
        echo '# Basic settings
CONFIG_ACPI=y
CONFIG_BASE_FULL=y
CONFIG_BLOCK=y
CONFIG_JUMP_LABEL=y
CONFIG_KERNEL_XZ=y
CONFIG_MULTIUSER=y
CONFIG_SHMEM=y
CONFIG_UNIX=y
# File system settings
CONFIG_DEVTMPFS=y
CONFIG_OVERLAY_FS=y
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
CONFIG_RETPOLINE=y
CONFIG_SECURITY_LOCKDOWN_LSM=y
CONFIG_SECURITY_LOCKDOWN_LSM_EARLY=y
CONFIG_STACKPROTECTOR=y
CONFIG_STACKPROTECTOR_STRONG=y
CONFIG_STRICT_KERNEL_RWX=y'
        [[ ${options[arch]} =~ 64 ]] && echo '# Architecture settings
CONFIG_64BIT=y'
        test "x${options[arch]}" = xx86_64 && echo 'CONFIG_SMP=y
CONFIG_X86_LOCAL_APIC=y'
        opt networkd && echo '# Network settings
CONFIG_NET=y
CONFIG_INET=y
CONFIG_IPV6=y
CONFIG_PACKET=y'
        opt nvme && echo '# NVMe settings
CONFIG_PCI=y
CONFIG_BLK_DEV_NVME=y'
        opt ramdisk && echo '# Initrd settings
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_XZ=y
# Loop settings
CONFIG_BLK_DEV=y
CONFIG_BLK_DEV_LOOP=y
CONFIG_BLK_DEV_LOOP_MIN_COUNT=1' || echo '# Loop settings
CONFIG_BLK_DEV_LOOP_MIN_COUNT=0'
        opt sb_key && opt sb_cert && echo '# Signing settings
CONFIG_MODULE_SIG=y
CONFIG_MODULE_SIG_ALL=y
CONFIG_MODULE_SIG_FORCE=y
CONFIG_MODULE_SIG_SHA512=y'
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
        echo '# Settings for systemd as decided by Gentoo, plus some missing
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
else $rm -f "$output/config.base"
fi > "$output/config.base"

function build_relabel_kernel() if opt selinux
then
        echo > "$output/config.relabel" '# Target the native CPU.
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
CONFIG_RD_XZ=y
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
make -C /usr/src/linux -j$(nproc) allnoconfig KCONFIG_ALLCONFIG="$PWD/config.relabel" V=1
make -C /usr/src/linux -j$(nproc) V=1
make -C /usr/src/linux install V=1
mv /boot/vmlinuz-* vmlinuz.relabel
rm -f /boot/*
exec make -C /usr/src/linux -j$(nproc) mrproper V=1
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
        local -r native=${1:-$DEFAULT_ARCH} target=${options[arch]}
        local -r nomulti=$([[ ${native: -2} = ${target: -2} || $target != *86* || $# -gt 0 ]] && echo /no-multilib)
        local -r selinux=${options[selinux]:+/selinux}
        case "$native" in
            aarch64)  echo default/linux/arm64/17.0/systemd ;;
            armv5tel) echo default/linux/arm/17.0/armv5te ;;
            armv7a)   echo default/linux/arm/17.0/armv7a ;;
            i[3-6]86) echo default/linux/x86/17.0/hardened$selinux ;;
            powerpc)  echo default/linux/ppc/17.0 ;;
            riscv64)  echo default/linux/riscv/17.0/rv64gc/lp64d ;;
            x86_64)   echo default/linux/amd64/17.1$nomulti/hardened$selinux ;;
            *) return 1 ;;
        esac
}

function archmap_stage3() {
        local -r native=${1:-$DEFAULT_ARCH} target=${options[arch]}
        local -r base="https://gentoo.osuosl.org/releases/$(archmap "$@")/autobuilds"
        local -r nomulti=$([[ ${native: -2} = ${target: -2} || $target != *86* ]] && echo +nomultilib)
        local -r selinux=${options[selinux]:+-selinux}

        local stage3
        case "$native" in
            armv5tel) stage3=stage3-armv5tel ;;
            armv7a)   stage3=stage3-armv7a_hardfp ;;
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
            emacs)
                echo 'media-libs/harfbuzz icu' >> "$buildroot/etc/portage/package.use/emacs.conf"
                echo 'MYCMAKEARGS="-DUSE_LD_GOLD:BOOL=OFF"' >> "$portage/env/no-gold.conf"
                echo 'net-libs/webkit-gtk no-gold.conf' >> "$portage/package.env/webkit-gtk.conf"
                $cat << 'EOF' >> "$portage/package.accept_keywords/emacs.conf"
<app-editors/emacs-28
media-libs/woff2
net-libs/webkit-gtk amd64
sys-apps/bubblewrap
sys-apps/xdg-dbus-proxy amd64
EOF
                echo app-editors/emacs >> "$portage/package.unmask/emacs.conf"
                script << 'EOF'
patch -d /var/db/repos/gentoo -p0 << 'EOP'
--- app-editors/emacs/emacs-27.0.90.ebuild
+++ app-editors/emacs/emacs-27.0.90.ebuild
@@ -250,6 +250,11 @@ src_configure() {
 		myconf+=" --without-x --without-ns"
 	fi
 
+	CFLAGS= CPPFLAGS= LDFLAGS= ./configure --without-all
+	make -j$(nproc) lisp {C,CPP,LD}FLAGS=
+	make -C lib-src -j$(nproc) blessmail {C,CPP,LD}FLAGS=
+	mv lib-src/make-docfile{,.save} ; mv lib-src/make-fingerprint{,.save}
+	make clean
 	econf \
 		--program-suffix="-${EMACS_SUFFIX}" \
 		--includedir="${EPREFIX}"/usr/include/${EMACS_SUFFIX} \
@@ -259,7 +264,7 @@ src_configure() {
 		--without-compress-install \
 		--without-hesiod \
 		--without-pop \
-		--with-dumping=pdumper \
+		--with-dumping=none --with-pdumper \
 		--with-file-notification=$(usev inotify || usev gfile || echo no) \
 		$(use_enable acl) \
 		$(use_with dbus) \
@@ -279,6 +284,9 @@ src_configure() {
 		$(use_with wide-int) \
 		$(use_with zlib) \
 		${myconf}
+	emake -C lib all
+	mv lib-src/make-docfile{.save,} ; mv lib-src/make-fingerprint{.save,}
+	touch lib-src/make-{docfile,fingerprint}
 }
 
 #src_compile() {
EOP
sed -i -e s/gnome2_giomodule_cache_update/:/g /var/db/repos/gentoo/net-libs/glib-networking/glib-networking-2.60.4.ebuild
ebuild /var/db/repos/gentoo/app-editors/emacs/emacs-27.0.90.ebuild manifest
ebuild /var/db/repos/gentoo/net-libs/glib-networking/glib-networking-2.60.4.ebuild manifest
EOF
                ;;
            firefox)
                echo 'CPU_FLAGS_X86=""' >> "$buildroot/etc/portage/env/no-cpu-flags.conf"
                $cat << 'EOF' >> "$buildroot/etc/portage/package.accept_keywords/firefox.conf"
=dev-lang/rust-1.41.1
dev-libs/nspr
dev-libs/nss
media-libs/libvpx
media-libs/libwebp
=virtual/rust-1.41.1
EOF
                echo 'media-libs/libaom no-cpu-flags.conf' >> "$buildroot/etc/portage/package.env/firefox.conf"
                echo 'dev-lang/rust ctarget.conf' >> "$buildroot/etc/portage/package.env/rust.conf"
                $cat << 'EOF' >> "$buildroot/etc/portage/package.use/firefox.conf"
dev-db/sqlite secure-delete
dev-lang/python sqlite
media-libs/libepoxy X
media-libs/libpng apng
media-libs/libvpx postproc
media-libs/mesa X
media-plugins/alsa-plugins pulseaudio
sys-devel/clang default-libcxx
x11-libs/gtk+ X
EOF
                echo 'BINDGEN_EXTRA_CLANG_ARGS="-target $CHOST --sysroot=$SYSROOT -I/usr/include/c++/v1"' >> "$portage/env/bindgen.conf"
                echo 'EGIT_OVERRIDE_COMMIT_AOM="01c7a66021087cb65d33bc73812d89dd0ecac644"' >> "$portage/env/libaom.conf"
                $cat << 'EOF' >> "$portage/package.accept_keywords/firefox.conf"
dev-db/sqlite
dev-libs/nspr
dev-libs/nss
media-libs/dav1d
media-libs/libaom **
media-libs/libvpx
media-libs/libwebp
www-client/firefox **
EOF
                $cat << 'EOF' >> "$portage/package.env/firefox.conf"
media-libs/libaom libaom.conf
www-client/firefox bindgen.conf
EOF
                echo 'www-client/firefox -cpu_flags_arm_neon' >> "$portage/package.use/firefox.conf"
                $mkdir -p "$portage/patches/media-video/ffmpeg"
                $cat << 'EOF' > "$portage/patches/media-video/ffmpeg/cross-native.patch"
--- a/configure
+++ b/configure
@@ -4733,6 +4733,7 @@
 fi
 
 if test "$cpu" = host; then
+    false &&
     enabled cross_compile &&
         true "--cpu=host makes no sense when cross-compiling."
 
EOF
                $mkdir -p "$portage/patches/www-client/firefox"
                test "x${options[arch]}" = xpowerpc &&
                $cat << 'EOF' > "$portage/patches/www-client/firefox/ppc.patch"
diff --git a/third_party/rust/authenticator/src/linux/ioctl_powerpcbe.rs b/third_party/rust/authenticator/src/linux/ioctl_powerpcbe.rs
new file mode 120000
index 0000000000..0a99c953b2
--- /dev/null
+++ b/third_party/rust/authenticator/src/linux/ioctl_powerpcbe.rs
@@ -0,0 +1 @@
+ioctl_powerpc64le.rs
\ No newline at end of file
--- a/gfx/wr/webrender/src/resource_cache.rs
+++ b/gfx/wr/webrender/src/resource_cache.rs
@@ -44,7 +44,7 @@
 #[cfg(any(feature = "capture", feature = "replay"))]
 use std::path::PathBuf;
 use std::sync::{Arc, RwLock};
-use std::sync::atomic::{AtomicU64, Ordering};
+use std::sync::atomic::{AtomicU32, Ordering};
 use std::time::SystemTime;
 use std::u32;
 use crate::texture_cache::{TextureCache, TextureCacheHandle, Eviction};
@@ -53,7 +53,7 @@
 const DEFAULT_TILE_SIZE: TileSize = 512;
 
 // Counter for generating unique native surface ids
-static NEXT_NATIVE_SURFACE_ID: AtomicU64 = AtomicU64::new(0);
+static NEXT_NATIVE_SURFACE_ID: AtomicU32 = AtomicU32::new(0);
 
 #[cfg_attr(feature = "capture", derive(Serialize))]
 #[cfg_attr(feature = "replay", derive(Deserialize))]
@@ -1786,7 +1786,7 @@
         tile_size: DeviceIntSize,
         is_opaque: bool,
     ) -> NativeSurfaceId {
-        let id = NativeSurfaceId(NEXT_NATIVE_SURFACE_ID.fetch_add(1, Ordering::Relaxed));
+        let id = NativeSurfaceId(NEXT_NATIVE_SURFACE_ID.fetch_add(1, Ordering::Relaxed).into());
 
         self.pending_native_surface_updates.push(
             NativeSurfaceOperation {
--- a/js/src/jit/none/MacroAssembler-none.h
+++ b/js/src/jit/none/MacroAssembler-none.h
@@ -99,7 +99,7 @@
 static constexpr Register WasmJitEntryReturnScratch{Registers::invalid_reg};
 
 static constexpr uint32_t ABIStackAlignment = 4;
-static constexpr uint32_t CodeAlignment = sizeof(void*);
+static constexpr uint32_t CodeAlignment = 8;
 static constexpr uint32_t JitStackAlignment = 8;
 static constexpr uint32_t JitStackValueAlignment =
     JitStackAlignment / sizeof(Value);
--- a/xpcom/reflect/xptcall/xptcall.h
+++ b/xpcom/reflect/xptcall/xptcall.h
@@ -71,6 +71,11 @@
     ExtendedVal ext;
   };
 
+#if defined(__powerpc__) && !defined(__powerpc64__)
+  // this field is still necessary on ppc32, as an address
+  // to it is taken certain places in xptcall
+  void *ptr;
+#endif
   nsXPTType type;
   uint8_t flags;
 
@@ -91,7 +96,12 @@
   };
 
   void ClearFlags() { flags = 0; }
+#if defined(__powerpc__) && !defined(__powerpc64__)
+  void SetIndirect() { ptr = &val; flags |= IS_INDIRECT; }
+  bool IsPtrData() const { return IsIndirect(); }
+#else
   void SetIndirect() { flags |= IS_INDIRECT; }
+#endif
 
   bool IsIndirect() const { return 0 != (flags & IS_INDIRECT); }
 

EOF
                script << 'EOG'
patch -d /var/db/repos/gentoo -p0 << 'EOP'
--- dev-lang/rust/rust-1.41.1.ebuild
+++ dev-lang/rust/rust-1.41.1.ebuild
@@ -162,16 +162,19 @@ src_prepare() {
 }
 
 src_configure() {
-	local rust_target="" rust_targets="" arch_cflags
+	local -A rust_targets
+	local rust_target="" arch_cflags
 
 	# Collect rust target names to compile standard libs for all ABIs.
 	for v in $(multilib_get_enabled_abi_pairs); do
-		rust_targets="${rust_targets},\"$(rust_abi $(get_abi_CHOST ${v##*.}))\""
+		rust_targets+=([$(rust_abi $(get_abi_CHOST ${v##*.}))]=1)
 	done
 	if use wasm; then
-		rust_targets="${rust_targets},\"wasm32-unknown-unknown\""
+		rust_targets+=([wasm32-unknown-unknown]=1)
+	fi
+	if [[ ${CTARGET:-${CHOST}} != ${CHOST} ]]; then
+		rust_targets+=([$(rust_abi ${CTARGET})]=1)
 	fi
-	rust_targets="${rust_targets#,}"
 
 	local extended="true" tools="\"cargo\","
 	if use clippy; then
@@ -204,7 +207,7 @@ src_configure() {
 		[build]
 		build = "${rust_target}"
 		host = ["${rust_target}"]
-		target = [${rust_targets}]
+		target = [$(printf -v t ',"%s"' "${!rust_targets[@]}" ; echo ${t#,})]
 		cargo = "${rust_stage0_root}/bin/cargo"
 		rustc = "${rust_stage0_root}/bin/rustc"
 		docs = $(toml_usex doc)
@@ -269,6 +272,18 @@ src_configure() {
 			linker = "$(usex system-llvm lld rust-lld)"
 		EOF
 	fi
+
+	if [[ ${CTARGET:-${CHOST}} != ${CHOST} ]]; then
+		rust_target=$(rust_abi ${CTARGET})
+		grep -Fqx "[target.${rust_target}]" "${S}"/config.toml ||
+		cat <<- EOF >> "${S}"/config.toml
+			[target.${rust_target}]
+			cc = "$(tc-getCC "${CTARGET}")"
+			cxx = "$(tc-getCXX "${CTARGET}")"
+			linker = "$(tc-getCC "${CTARGET}")"
+			ar = "$(tc-getAR "${CTARGET}")"
+		EOF
+	fi
 }
 
 src_compile() {
EOP
sed -i -e 's/.*lto.*gold/#&/' /var/db/repos/gentoo/www-client/firefox/firefox-74.0-r1.ebuild
compgen -G '/usr/*/etc/portage/patches/www-client/firefox/ppc.patch' &&
sed -i -e '/final/imozconfig_annotate "too lazy to port to ppc" --disable-webrtc ; sed -i -e /elf-hack/d "${S}"/.mozconfig' /var/db/repos/gentoo/www-client/firefox/firefox-74.0-r1.ebuild
ebuild /var/db/repos/gentoo/dev-lang/rust/rust-1.41.1.ebuild manifest
ebuild /var/db/repos/gentoo/www-client/firefox/firefox-74.0-r1.ebuild manifest
EOG
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
                usr/include
                'usr/lib/lib*.a'
                usr/lib/gcc
                usr/{lib,share}/pkgconfig
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
