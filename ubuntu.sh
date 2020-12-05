packages=()
packages_buildroot=()

DEFAULT_RELEASE=20.10

function create_buildroot() {
        local -Ar releasemap=([20.04]=focal [20.10]=groovy)
        local -r release=${options[release]:=$DEFAULT_RELEASE}
        local -r name=${releasemap[$release]?Unsupported release version}
        local -r image="https://cloud-images.ubuntu.com/minimal/releases/$name/release/ubuntu-$release-minimal-cloudimg-$(archmap)-root.tar.xz"

        opt bootable && packages_buildroot+=(dracut linux-image-generic)
        opt gpt && opt uefi && packages_buildroot+=(dosfstools mtools)
        opt read_only && ! opt squash && packages_buildroot+=(erofs-utils)
        opt secureboot && packages_buildroot+=(pesign)
        opt selinux && packages_buildroot+=(busybox linux-image-generic policycoreutils qemu-system-x86)
        opt uefi && packages_buildroot+=(binutils imagemagick ubuntu-mono)
        opt verity_sig && opt bootable && packages_buildroot+=(keyutils linux-headers-generic)
        packages_buildroot+=(debootstrap libglib2.0-bin)

        $mkdir -p "$buildroot"
        $curl -L "${image%/*}/SHA256SUMS" > "$output/checksum"
        $curl -L "${image%/*}/SHA256SUMS.gpg" > "$output/checksum.sig"
        $curl -L "$image" > "$output/image.tar.xz"
        verify_distro "$output"/checksum{,.sig} "$output/image.tar.xz"
        $tar --exclude=etc/resolv.conf -C "$buildroot" -xJf "$output/image.tar.xz"
        $rm -f "$output"/checksum{,.sig} "$output/image.tar.xz"

        configure_initrd_generation
        initialize_buildroot

        script "${packages_buildroot[@]}" "$@" << 'EOF'
export DEBIAN_FRONTEND=noninteractive INITRD=No
apt-get update
apt-get --assume-yes --option=Acquire::Retries=5 upgrade --with-new-pkgs
exec apt-get --assume-yes --option=Acquire::Retries=5 install "$@"
EOF

        # Fix the old pesign option name.
        test ! -e "$buildroot/etc/popt.d/pesign.popt" ||
        echo 'pesign alias --certificate --certficate' >> "$buildroot/etc/popt.d/pesign.popt"
}

function install_packages() {
        opt bootable || opt networkd && packages+=(libpam-systemd)
        opt selinux && packages+=(selinux-policy-default)

        mount -o bind,X-mount.mkdir {,root}/var/cache/apt
        trap -- 'umount root/var/cache/apt ; trap - RETURN' RETURN

        debootstrap \
            ${options[arch]:+--arch="$(archmap "${options[arch]}")"} \
            --force-check-gpg \
            --merged-usr \
            --variant=minbase \
            "$(sed -n s/^UBUNTU_CODENAME=//p /etc/os-release)" \
            root http://archive.ubuntu.com/ubuntu

        local -rx DEBIAN_FRONTEND=noninteractive INITRD=No
        cp -p {,root}/etc/apt/sources.list
        for dir in dev proc sys ; do mount --bind {,root}/"$dir" ; done
        trap -- 'umount root/{dev,proc,sys,var/cache/apt} ; trap - RETURN' RETURN
        chroot root /usr/bin/apt-get update
        chroot root /usr/bin/apt-get --assume-yes --option=Acquire::Retries=5 upgrade --with-new-pkgs
        chroot root /usr/bin/apt-get --assume-yes --option=Acquire::Retries=5 install "${packages[@]}" "$@"

        dpkg-query --show > packages-buildroot.txt
        dpkg-query --admindir=root/var/lib/dpkg --show > packages.txt
}

function distro_tweaks() {
        rm -fr root/etc/kernel root/etc/rc.d

        # The default policy does not differentiate root's home directory.
        test -s root/usr/lib/systemd/system/root.mount &&
        sed -i -e s/admin_home/user_home_dir/g root/usr/lib/systemd/system/root.mount

        # Default to the nftables firewall interface if it was built.
        local cmd ; for cmd in iptables ip6tables
        do
                test -x "root/usr/sbin/$cmd-nft" &&
                chroot root /usr/bin/update-alternatives --set "$cmd" "/usr/sbin/$cmd-nft"
        done

        test -s root/usr/lib/systemd/system/console-setup.service &&
        ln -fst root/usr/lib/systemd/system/multi-user.target.wants ../console-setup.service

        test -s root/usr/share/systemd/tmp.mount &&
        mv -t root/usr/lib/systemd/system root/usr/share/systemd/tmp.mount

        test -s root/etc/inputrc &&
        sed -i -e '/history-search/s/^[# ]*//' root/etc/inputrc

        test -s root/etc/default/keyboard &&
        sed -i -e '/^XKBOPTIONS=""$/s/""/"ctrl:nocaps"/' root/etc/default/keyboard &&
        compgen -G 'root/usr/share/keymaps/i386/qwerty/emacs2.*' &&
        echo 'KMAP="emacs2"' >> root/etc/default/keyboard

        test -s root/etc/default/locale ||
        echo LANG=C.UTF-8 > root/etc/default/locale

        sed -i \
            -e "/^ *PS1='/s/.{deb/\$? &/p" \
            -e '/force_color_prompt=yes/s/^#*//' \
            root/etc/{bash,skel/}.bashrc

        # Pick yellow/orange as the Ubuntu distro color.
        echo 'ANSI_COLOR="1;33"' >> root/etc/os-release
}

function save_boot_files() if opt bootable
then
        opt uefi && test ! -s logo.bmp &&
        sed '/<svg/{s/"22"/"640"/g;s/>/ viewBox="0 0 22 22">/;}' /usr/share/icons/ubuntu-mono-dark/apps/22/distributor-logo.svg > /root/logo.svg &&
        convert -background none /root/logo.svg -color-matrix '0 1 0 0 0 0 1 0 0 0 0 1 1 0 0 0' logo.bmp
        test -s initrd.img || build_systemd_ramdisk "$(cd /lib/modules ; compgen -G '[0-9]*')"
        test -s vmlinuz || cp -pt . /boot/vmlinuz
        if opt verity_sig
        then
                local -r v=$(echo /lib/modules/[0-9]*-generic)
                "$v/build/scripts/extract-vmlinux" "/boot/vmlinuz-${v##*/}" > vmlinux
                "$v/build/scripts/insert-sys-cert" -b vmlinux -c "$keydir/verity.der" -s "/boot/System.map-${v##*/}"
        fi
fi

function configure_initrd_generation() if opt bootable
then
        # Don't expect that the build system is the target system.
        $mkdir -p "$buildroot/etc/dracut.conf.d"
        $cat << 'EOF' > "$buildroot/etc/dracut.conf.d/99-settings.conf"
hostonly="no"
reproducible="yes"
EOF

        # Load NVMe support before verity so dm-init can find the partition.
        if opt nvme
        then
                $mkdir -p "$buildroot/usr/lib/modprobe.d"
                echo > "$buildroot/usr/lib/modprobe.d/nvme-verity.conf" \
                    'softdep dm-verity pre: nvme'
        fi

        # Since systemd can't skip canonicalization, wait for a udev hack.
        if opt verity
        then
                local dropin=/usr/lib/systemd/system/sysroot.mount.d
                $mkdir -p "$buildroot$dropin"
                echo > "$buildroot$dropin/verity-root.conf" '[Unit]
After=dev-mapper-root.device
Requires=dev-mapper-root.device'
                echo >> "$buildroot/etc/dracut.conf.d/99-settings.conf" \
                    "install_optional_items+=\" $dropin/verity-root.conf \""
        fi

        # Create a generator to handle verity ramdisks since dm-init can't.
        opt verity && if opt ramdisk || opt verity_sig
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
echo > "$rundir/dmsetup-verity-root.service" "[Unit]
DefaultDependencies=no
After=$device
Requires=$device
[Service]
ExecStart=/bin/sh -c \"test -s /wd/verity.sig &&\
 keyctl padd user verity:root @s < /wd/verity.sig ;\
 exec dmsetup create --concise '\'\$concise\''\"
RemainAfterExit=yes
Type=oneshot"
mkdir -p "$rundir/dev-dm\x2d0.device.requires"
ln -fst "$rundir/dev-dm\x2d0.device.requires" ../dmsetup-verity-root.service'
                $chmod 0755 "$buildroot$gendir/dmsetup-verity-root"
                echo >> "$buildroot/etc/dracut.conf.d/99-settings.conf" \
                    'install_optional_items+="' \
                    "$gendir/dmsetup-verity-root" \
                    /wd/verity.sig '"'
        else
                local dropin=/usr/lib/systemd/system/dev-dm\\x2d0.device.requires
                $mkdir -p "$buildroot$dropin"
                $ln -fst "$buildroot$dropin" ../udev-workaround.service
                echo > "$buildroot${dropin%/*}/udev-workaround.service" '[Unit]
DefaultDependencies=no
After=systemd-udev-trigger.service
[Service]
ExecStart=/usr/bin/udevadm trigger
RemainAfterExit=yes
Type=oneshot'
                echo >> "$buildroot/etc/dracut.conf.d/99-settings.conf" \
                    'install_optional_items+="' \
                    "$dropin/udev-workaround.service" \
                    "${dropin%/*}/udev-workaround.service" \
                    '"'
        fi

        # Load overlayfs in the initrd in case modules aren't installed.
        if opt read_only
        then
                $mkdir -p "$buildroot/usr/lib/modules-load.d"
                echo overlay > "$buildroot/usr/lib/modules-load.d/overlay.conf"
        fi
fi

# Override relabeling to fix pthread_cancel and broken QEMU display behavior.
eval "$(declare -f relabel | $sed \
    -e '/ldd/iopt squash && cp -t "$root/lib" /usr/lib/*/libgcc_s.so.1' \
    -e 's/qemu-system-[^ ]* /&-display none /g')"

# Override kernel arguments to use SELinux instead of AppArmor.
eval "$(
declare -f relabel | $sed 's/ -append /&security=selinux" "/'
declare -f kernel_cmdline | $sed 's/^ *echo /&${options[selinux]:+security=selinux} /'
)"

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

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
=+MFT
-----END PGP PUBLIC KEY BLOCK-----
EOF
        $gpg --verify "$2"
        test x$($sed -n 's/ .*root.tar.xz$//p' "$1") = x$($sha256sum "$3" | $sed -n '1s/ .*//p')
}

function archmap() case "${*:-$DEFAULT_ARCH}" in
    i[3-6]86) echo i386 ;;
    x86_64)   echo amd64 ;;
    *) return 1 ;;
esac
