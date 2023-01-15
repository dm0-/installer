# SPDX-License-Identifier: GPL-3.0-or-later
packages_buildroot=()

options[selinux]=
options[uefi_vars]=
options[verity_sig]=

function create_buildroot() {
        local -r dir="https://mirrors.kernel.org/archlinux/iso/latest"
        local -r release=$($curl -L "$dir/sha256sums.txt" | $sed -n 's/.*-bootstrap-\([0-9.]*\)-.*/\1/p')
        local -r image="$dir/archlinux-bootstrap-$release-$DEFAULT_ARCH.tar.gz"

        opt bootable && packages_buildroot+=(dracut linux-hardened)
        opt bootable && [[ ${options[arch]:-$DEFAULT_ARCH} == *[3-6x]86* ]] && packages_buildroot+=(intel-ucode linux-firmware)
        opt gpt && opt uefi && packages_buildroot+=(dosfstools mtools)
        opt read_only && ! opt squash && packages_buildroot+=(erofs-utils)
        opt secureboot && packages_buildroot+=(pesign)
        opt squash && packages_buildroot+=(squashfs-tools)
        opt uefi && packages_buildroot+=(binutils librsvg imagemagick)
        opt uefi_vars && packages_buildroot+=(qemu-system-x86)

        $curl -L "$image.sig" > "$output/image.tgz.sig"
        $curl -L "$image" > "$output/image.tgz"
        verify_distro "$output"/image.tgz{.sig,}
        $tar --strip-components=1 -C "$buildroot" -xzf "$output/image.tgz"
        $rm -f "$output"/image.tgz{.sig,}

        # Use the kernel.org and mit.edu mirrors with parallel downloads.
        $sed -i \
            -e '/https.*kernel.org/s/^#*//' \
            -e '/https.*mit.edu/s/^#*//' \
            "$buildroot/etc/pacman.d/mirrorlist"
        $sed -i -e '/^#ParallelDownloads/s/^#//' "$buildroot/etc/pacman.conf"

        configure_initrd_generation
        initialize_buildroot "$@"

        script "${packages_buildroot[@]}" << 'EOF'
pacman-key --init
pacman-key --populate archlinux
pacman --noconfirm --sync --needed --refresh{,} --sysupgrade{,} "$@"

# Work around Arch not providing Intel microcode so dracut can find it.
if test -e /boot/intel-ucode.img
then
        mkdir -p /lib/firmware/intel-ucode
        cpio --to-stdout -i < /boot/intel-ucode.img > /lib/firmware/intel-ucode/all.img
fi
EOF
}

function install_packages() {
        opt bootable || opt networkd && packages+=(systemd)
        opt networkd && packages+=(gnutls)

        mkdir -p root/var/lib/pacman
        mount -o bind,X-mount.mkdir {,root}/var/cache/pacman
        trap -- 'umount root/var/cache/pacman ; trap - RETURN' RETURN

        mkdir -p root/usr/local/bin  # Work around a broken post_install.
        ln -fns ../../bin/true root/usr/local/bin/dirmngr
        pacman --noconfirm --root=root \
            --sync --refresh --sysupgrade "${packages[@]:-filesystem}" "$@"
        rm -f root/usr/local/bin/dirmngr

        # Create a UTF-8 locale so things work.
        localedef --prefix=root -c -f UTF-8 -i en_US en_US.UTF-8

        # Define basic users and groups prior to configuring other stuff.
        test -e root/usr/lib/sysusers.d/basic.conf &&
        systemd-sysusers --root=root basic.conf

        # List everything installed in the image and what was used to build it.
        pacman --query > packages-buildroot.txt
        pacman --root=root --query > packages.txt
}

function distro_tweaks() {
        test -s root/etc/inputrc && sed -i \
            -e '/5.*g-of-history/s/: .*/: history-search-backward/' \
            -e '/6.*d-of-history/s/: .*/: history-search-forward/' \
            root/etc/inputrc

        sed -i -e "s/^PS1='./&\$? /" root/etc/{bash,skel/}.bashrc
        echo "alias ll='ls -l'" >> root/etc/skel/.bashrc
}

function save_boot_files() if opt bootable
then
        opt uefi && test ! -s logo.bmp &&
        sed /m2/d /usr/share/pixmaps/archlinux-logo.svg > /root/logo.svg &&
        magick -background none /root/logo.svg -color-matrix '0 1 0 0 0 0 0 1 0 0 0 0 0 0 1 0 0 0 1 0 1 0 0 0 0' logo.bmp
        test -s initrd.img || build_systemd_ramdisk "$(cd /lib/modules ; compgen -G '[0-9]*')"
        test -s vmlinuz || cp -pt . /lib/modules/*/vmlinuz
fi

# Override dm-init with userspace since the Arch kernel doesn't enable it.
eval "$(declare -f kernel_cmdline | $sed 's/opt ramdisk[ &]*dmsetup=/dmsetup=/')"

# Override default OVMF paths for this distro's packaging.
eval "$(declare -f set_uefi_variables | $sed \
    -e 's,/usr/\S*VARS\S*.fd,/usr/share/edk2-ovmf/x64/OVMF_VARS.fd,' \
    -e 's,/usr/\S*CODE\S*.fd,/usr/share/edk2-ovmf/x64/OVMF_CODE.secboot.fd,' \
    -e 's,/usr/\S*/Shell.efi,/usr/share/edk2-shell/x64/Shell.efi,' \
    -e 's,/usr/\S*/EnrollDefaultKeys.efi,,')"

function configure_initrd_generation() if opt bootable
then
        # Don't expect that the build system is the target system.
        $mkdir -p "$buildroot/etc/dracut.conf.d"
        $cat << EOF > "$buildroot/etc/dracut.conf.d/99-settings.conf"
add_drivers+=" ${options[ramdisk]:+loop} "
compress="zstd --threads=0 --ultra -22"
hostonly="no"
i18n_install_all="no"
reproducible="yes"
EOF

        # Create a generator to handle verity since dm-init isn't enabled.
        if opt verity
        then
                local -r gendir=/usr/lib/systemd/system-generators
                $mkdir -p "$buildroot$gendir"
                echo > "$buildroot$gendir/dmsetup-verity-root" '#!/bin/bash -eu
read -rs cmdline < /proc/cmdline
[[ $cmdline == *DVR=\"*\"* ]] || exit 0
concise=${cmdline##*DVR=\"} concise=${concise%%\"*}
device=${concise#* * * * } device=${device%% *}
if [[ $device =~ ^[A-Z]+= ]]
then
        tag=${device%%=*} tag=${tag,,}
        device=${device#*=}
        [[ $tag == partuuid ]] && device=${device,,}
        device="/dev/disk/by-$tag/$device"
fi
device=$(systemd-escape --path "$device").device
rundir=/run/systemd/system
mkdir -p "$rundir/sysroot.mount.d"
echo > "$rundir/dmsetup-verity-root.service" "[Unit]
DefaultDependencies=no
After=$device
Requires=$device
[Service]
ExecStart=/usr/sbin/dmsetup create --concise \"$concise\"
RemainAfterExit=yes
Type=oneshot"
echo > "$rundir/sysroot.mount.d/verity-root.conf" "[Unit]
After=dev-mapper-root.device dmsetup-verity-root.service
Requires=dev-mapper-root.device dmsetup-verity-root.service"'
                $chmod 0755 "$buildroot$gendir/dmsetup-verity-root"
                echo >> "$buildroot/etc/dracut.conf.d/99-settings.conf" \
                    "install_optional_items+=\" $gendir/dmsetup-verity-root \""
        fi

        # Load overlayfs in the initrd in case modules aren't installed.
        if opt read_only
        then
                $mkdir -p "$buildroot/usr/lib/modules-load.d"
                echo overlay > "$buildroot/usr/lib/modules-load.d/overlay.conf"
        fi
fi

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import
        $gpg --verify "$1" "$2"
} << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mDMEY1+RVxYJKwYBBAHaRw8BAQdAd3XdZwOmmiALePwd26Bu3hPblAfHflGN+Lud
gE2Qyby0JVBpZXJyZSBTY2htaXR6IDxwaWVycmVAYXJjaGxpbnV4Lm9yZz6ImQQT
FggAQQIbAwUJHDIEgAULCQgHAgYVCgkICwIEFgIDAQIeAQIXgBYhBD6AyhqLifac
ulfZinal75BURJpcBQJjX5NoAhkBAAoJEHal75BURJpctA8BAIV45djib0s98wM3
Os4gSUvKH7D2n08FrzQCwCyNcYLWAQDL1iZzeOcCPYwkOdvLdvlbI3MNuMEwpWG/
YK+YOWfQCrQkUGllcnJlIFNjaG1pdHogPHBpZXJyZUBhcmNobGludXguZGU+iJYE
ExYIAD4CGwMFCRwyBIAFCwkIBwIGFQoJCAsCBBYCAwECHgECF4AWIQQ+gMoai4n2
nLpX2Yp2pe+QVESaXAUCY1+TaAAKCRB2pe+QVESaXN2LAP0d/tMN/EGsnVjCkP2U
u1RUjgqnN7c/l145vlESwYTmhwEA+ftbKY8WhNR+uvF+aWypm1LP7YPkZ1cRZBg5
OpS+7Qy4MwRjX5HTFgkrBgEEAdpHDwEBB0DjSWuxVrnVYEIcJlRJPmn54ReBGvqP
+EYB2BVx5ZFPv4h+BBgWCAAmFiEEPoDKGouJ9py6V9mKdqXvkFREmlwFAmNfkdMC
GyAFCRwyBIAACgkQdqXvkFREmlzEGwEAwvDuiUn1Mgw0x7/m0hXzveAAgLVdJWD+
0/YiepxE9GoA/jCgNca2AuWyi416FYQkFtqtlIjWUb56hY5WlBvpNZIOuDgEY1+R
VxIKKwYBBAGXVQEFAQEHQIhe0t8UMpN+G4c24ByW/Y1vu1m3C62KsvlRPzw/R0AN
AwEIB4h+BBgWCAAmFiEEPoDKGouJ9py6V9mKdqXvkFREmlwFAmNfkVcCGwwFCRwy
BIAACgkQdqXvkFREmlynZgD+PlibATlapVxz6EprGMfnktevUlfWQwShRJ+w/x8I
zyAA/0nOvoE7j4sdvg4QoW/s2nPYaDy8EK/XAMRT15eScYIH
=ttGH
-----END PGP PUBLIC KEY BLOCK-----
EOF
