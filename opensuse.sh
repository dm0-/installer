packages=(aaa_base branding-openSUSE openSUSE-release)
packages_buildroot=()

options[verity_sig]=

function create_buildroot() {
        local -r image="https://download.opensuse.org/tumbleweed/appliances/opensuse-tumbleweed-image.$DEFAULT_ARCH-lxc.tar.xz"

        opt bootable && packages_buildroot+=(kernel-default ucode-{amd,intel})
        opt gpt && opt uefi && packages_buildroot+=(dosfstools mtools)
        opt read_only && ! opt squash && packages_buildroot+=(erofs-utils)
        opt secureboot && packages_buildroot+=(mozilla-nss-tools pesign)
        opt selinux && packages_buildroot+=(busybox kernel-default policycoreutils qemu-x86)
        opt squash && packages_buildroot+=(squashfs)
        opt uefi && packages_buildroot+=(binutils distribution-logos-openSUSE-Tumbleweed ImageMagick)
        opt verity && packages_buildroot+=(cryptsetup device-mapper)
        packages_buildroot+=(curl e2fsprogs glib2-tools)

        $mkdir -p "$buildroot"
        $curl -L "$image.sha256" > "$output/checksum"
        $curl -L "$image.sha256.asc" > "$output/checksum.sig"
        $curl -L "$image" > "$output/image.tar.xz"
        verify_distro "$output"/checksum{,.sig} "$output/image.tar.xz"
        $tar -C "$buildroot" -xJf "$output/image.tar.xz"
        $rm -f "$output"/checksum{,.sig} "$output/image.tar.xz"

        # Disable non-OSS packages by default.
        $sed -i -e '/^enabled=/s/=.*/=0/' "$buildroot/etc/zypp/repos.d/repo-non-oss.repo"

        # Bypass license checks since it is abused to display random warnings.
        $sed -i -e 's/^[# ]*\(autoAgreeWithLicenses\) *=.*/\1 = yes/' \
            "$buildroot/etc/zypp/zypper.conf"

        configure_initrd_generation
        enable_selinux_repo
        initialize_buildroot

        enter /usr/bin/zypper --non-interactive update
        enter /usr/bin/zypper --non-interactive \
            install --allow-vendor-change "${packages_buildroot[@]}" "$@"

        # Let the configuration decide if the system should have documentation.
        $sed -i -e 's/^rpm.install.excludedocs/# &/' "$buildroot/etc/zypp/zypp.conf"
}

function install_packages() {
        opt bootable || opt networkd && packages+=(systemd)
        opt selinux && packages+=(selinux-policy-targeted)

        opt arch && sed -i -e "s/^[# ]*arch *=.*/arch = ${options[arch]}/" /etc/zypp/zypp.conf
        zypper --non-interactive --installroot="$PWD/root" \
            install "${packages[@]:-filesystem}" "$@" || [ 107 -eq "$?" ]

        # Define basic users and groups prior to configuring other stuff.
        grep -qs '^wheel:' root/etc/group ||
        groupadd --prefix root --system --gid=10 wheel

        # List everything installed in the image and what was used to build it.
        rpm -qa | sort > packages-buildroot.txt
        rpm --root="$PWD/root" -qa | sort > packages.txt
}

function distro_tweaks() {
        rm -fr root/etc/init.d root/etc/modprobe.d/60-blacklist_fs-erofs.conf

        test -s root/usr/share/systemd/tmp.mount &&
        mv -t root/usr/lib/systemd/system root/usr/share/systemd/tmp.mount

        test -s root/etc/zypp/repos.d/repo-non-oss.repo &&
        sed -i -e '/^enabled=/s/=.*/=0/' root/etc/zypp/repos.d/repo-non-oss.repo

        test -s root/usr/share/glib-2.0/schemas/openSUSE-branding.gschema.override &&
        mv root/usr/share/glib-2.0/schemas/{,50_}openSUSE-branding.gschema.override

        test -s root/usr/lib/systemd/system/polkit.service &&
        sed -i -e '/^Type=/iStateDirectory=polkit' root/usr/lib/systemd/system/polkit.service

        test -s root/etc/pam.d/common-auth &&
        sed -i -e 's/try_first_pass/& nullok/' root/etc/pam.d/common-auth

        test -s root/etc/sysconfig/selinux-policy &&
        sed -i \
            -e '/^SELINUX=/s/=.*/=permissive/' \
            -e '/^SELINUXTYPE=/s/=.*/=targeted/' \
            root/etc/selinux/config

        sed -i -e '1,/ PS1=/s/ PS1="/&$? /' root/etc/bash.bashrc
        echo "alias ll='ls -l'" >> root/etc/skel/.alias
}

function save_boot_files() if opt bootable
then
        opt uefi && test ! -s logo.bmp &&
        sed '/<svg/,/>/s,>,&<style>#g885{display:none}</style>,' /usr/share/pixmaps/distribution-logos/light-dual-branding.svg > /root/logo.svg &&
        magick -background none -size 720x320 /root/logo.svg -color-matrix '0 1 0 0 0 0 0 1 0 0 0 0 0 0 1 0 0 0 1 0 1 0 0 0 0' logo.bmp
        test -s initrd.img || build_systemd_ramdisk "$(cd /lib/modules ; compgen -G "$(rpm -q --qf '%{VERSION}' kernel-default)*")"
        test -s vmlinuz || cp -pt . /boot/vmlinuz
fi

# Override relabeling to add the missing disk driver and fix pthread_cancel.
eval "$(declare -f relabel | $sed \
    -e '/ldd/iopt squash && cp -t "$root/lib" /lib*/libgcc_s.so.1' \
    -e '/find/iln -fns busybox "$root/bin/insmod"\
xz -cd /lib/modules/*/*/drivers/ata/ata_piix.ko.xz > "$root/lib/ata_piix.ko"\
sed -i -e "/sda/iinsmod /lib/ata_piix.ko" "$root/init"')"

# Override kernel arguments to use SELinux instead of AppArmor.
eval "$(
declare -f relabel | $sed 's/ -append /&security=selinux" "/'
declare -f kernel_cmdline | $sed 's/^ *echo /&${options[selinux]:+security=selinux} /'
)"

# Override squashfs creation since openSUSE doesn't support zstd.
eval "$(declare -f relabel squash | $sed 's/ zstd .* 22 / xz /')"

# Override dm-init with userspace since the openSUSE kernel doesn't enable it.
eval "$(declare -f kernel_cmdline | $sed 's/opt ramdisk[ &]*dmsetup=/dmsetup=/')"

function configure_initrd_generation() if opt bootable
then
        # Don't expect that the build system is the target system.
        $mkdir -p "$buildroot/etc/dracut.conf.d"
        $cat << 'EOF' > "$buildroot/etc/dracut.conf.d/99-settings.conf"
hostonly="no"
reproducible="yes"
EOF

        # Create a generator to handle verity since dm-init isn't enabled.
        if opt verity
        then
                local -r gendir=/usr/lib/systemd/system-generators
                $mkdir -p "$buildroot$gendir"
                echo > "$buildroot$gendir/dmsetup-verity-root" '#!/bin/bash -eu
read -rs cmdline < /proc/cmdline
test "x${cmdline}" != "x${cmdline%%DVR=\"*\"*}" || exit 0
concise=${cmdline##*DVR=\"} concise=${concise%%\"*}
device=${concise#* * * * } device=${device%% *}
if [[ $device =~ ^[A-Z]+= ]]
then
        tag=${device%%=*} tag=${tag,,}
        device=${device#*=}
        [ $tag = partuuid ] && device=${device,,}
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

function enable_selinux_repo() if opt selinux
then
        local -r repo='https://download.opensuse.org/repositories/security:/SELinux/openSUSE_Factory'
        $curl -L "$repo/repodata/repomd.xml.key" > "$output/selinux.key"
        test x$($sha256sum "$output/selinux.key" | $sed -n '1s/ .*//p') = \
            x32af8322c657e308ab97aea20dc7c57a37a20b2e0ce5bf83b9945028ceb1e172
        enter /usr/bin/rpmkeys --import selinux.key
        $rm -f "$output/selinux.key"
        echo -e > "$buildroot/etc/zypp/repos.d/selinux.repo" \
            "[selinux]\nenabled=1\nautorefresh=1\nbaseurl=$repo\ngpgcheck=1"
fi

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQENBEkUTD8BCADWLy5d5IpJedHQQSXkC1VK/oAZlJEeBVpSZjMCn8LiHaI9Wq3G
3Vp6wvsP1b3kssJGzVFNctdXt5tjvOLxvrEfRJuGfqHTKILByqLzkeyWawbFNfSQ
93/8OunfSTXC1Sx3hgsNXQuOrNVKrDAQUqT620/jj94xNIg09bLSxsjN6EeTvyiO
mtE9H1J03o9tY6meNL/gcQhxBvwuo205np0JojYBP0pOfN8l9hnIOLkA0yu4ZXig
oKOVmf4iTjX4NImIWldT+UaWTO18NWcCrujtgHueytwYLBNV5N0oJIP2VYuLZfSD
VYuPllv7c6O2UEOXJsdbQaVuzU1HLocDyipnABEBAAG0NG9wZW5TVVNFIFByb2pl
Y3QgU2lnbmluZyBLZXkgPG9wZW5zdXNlQG9wZW5zdXNlLm9yZz6JATwEEwECACYC
GwMGCwkIBwMCBBUCCAMEFgIDAQIeAQIXgAUCU2dN1AUJHR8ElQAKCRC4iy/UPb3C
hGQrB/9teCZ3Nt8vHE0SC5NmYMAE1Spcjkzx6M4r4C70AVTMEQh/8BvgmwkKP/qI
CWo2vC1hMXRgLg/TnTtFDq7kW+mHsCXmf5OLh2qOWCKi55Vitlf6bmH7n+h34Sha
Ei8gAObSpZSF8BzPGl6v0QmEaGKM3O1oUbbB3Z8i6w21CTg7dbU5vGR8Yhi9rNtr
hqrPS+q2yftjNbsODagaOUb85ESfQGx/LqoMePD+7MqGpAXjKMZqsEDP0TbxTwSk
4UKnF4zFCYHPLK3y/hSH5SEJwwPY11l6JGdC1Ue8Zzaj7f//axUs/hTC0UZaEE+a
5v4gbqOcigKaFs9Lc3Bj8b/lE10Y
=i2TA
-----END PGP PUBLIC KEY BLOCK-----
EOF
        $gpg --verify "$2"
        test x$($sed -n 's/  .*//p' "$1") = x$($sha256sum "$3" | $sed -n '1s/ .*//p')
}

# OPTIONAL (IMAGE)

function drop_package() while read -rs
do exclude_paths+=("${REPLY#/}")
done < <(rpm --root="$PWD/root" -qal "$@")
