# SPDX-License-Identifier: GPL-3.0-or-later
packages_buildroot=()

options[enforcing]=
options[loadpin]=
options[uefi_vars]=

DEFAULT_RELEASE=23.10

function create_buildroot() {
        local -r release=${options[release]:=$DEFAULT_RELEASE}
        local -r name=$(releasemap "$release")
        local -r image="https://cloud-images.ubuntu.com/minimal/releases/$name/release/ubuntu-$release-minimal-cloudimg-$(archmap)-root.tar.xz"

        opt bootable && packages_buildroot+=(dracut linux-image-generic zstd)
        opt gpt && opt uefi && packages_buildroot+=(dosfstools mtools)
        opt read_only && ! opt squash && packages_buildroot+=(erofs-utils)
        opt secureboot && packages_buildroot+=(pesign)
        opt selinux && packages_buildroot+=(busybox linux-image-generic policycoreutils qemu-system-x86 zstd)
        opt uefi && packages_buildroot+=(binutils gawk imagemagick librsvg2-bin systemd-boot-efi ubuntu-mono)
        opt uefi_vars && packages_buildroot+=(ovmf qemu-system-x86)
        opt verity && packages_buildroot+=(cryptsetup-bin)
        opt verity_sig && opt bootable && packages_buildroot+=(keyutils linux-headers-generic)
        packages_buildroot+=(debootstrap gpg libglib2.0-bin)

        $curl -L "${image%/*}/SHA256SUMS" > "$output/checksum"
        $curl -L "${image%/*}/SHA256SUMS.gpg" > "$output/checksum.sig"
        $curl -L "$image" > "$output/image.txz"
        verify_distro "$output"/checksum{,.sig} "$output/image.txz"
        $tar --exclude=etc/resolv.conf -C "$buildroot" -xJf "$output/image.txz"
        $rm -f "$output"/checksum{,.sig} "$output/image.txz"

        # Configure the package manager to behave sensibly.
        $cat << 'EOF' >> "$buildroot/etc/apt/apt.conf.d/50fix-apt"
Acquire::Retries "5";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF

        configure_initrd_generation
        initialize_buildroot "$@"

        script "${packages_buildroot[@]}" << 'EOF'
export DEBIAN_FRONTEND=noninteractive INITRD=No
apt update
apt --assume-yes upgrade --with-new-pkgs
exec apt --assume-yes install "$@"
EOF

        # Fix the old pesign option name.
        ! opt secureboot ||
        $sed -n '/certficate/q0;$q1' "$buildroot/etc/popt.d/pesign.popt" ||
        echo 'pesign alias --certificate --certficate' >> "$buildroot/etc/popt.d/pesign.popt"
}

function install_packages() {
        opt bootable || opt networkd && packages+=(libpam-systemd)
        opt networkd && packages+=(systemd-resolved)
        opt selinux && packages+=("selinux-policy-${options[selinux]}")

        mount -o bind,X-mount.mkdir {,root}/var/cache/apt
        trap -- 'umount root/var/cache/apt ; trap - RETURN' RETURN

        debootstrap \
            ${options[arch]:+--arch="$(archmap "${options[arch]}")"} \
            --force-check-gpg \
            --include=ca-certificates \
            --merged-usr \
            --variant=minbase \
            "$(releasemap)" root http://archive.ubuntu.com/ubuntu

        # Configure the package manager to behave sensibly.
        cat << 'EOF' >> root/etc/apt/apt.conf.d/50fix-apt
Acquire::Retries "5";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF

        local -rx DEBIAN_FRONTEND=noninteractive INITRD=No
        cp -p {,root}/etc/apt/sources.list
        for dir in dev proc sys ; do mount --bind {,root}/"$dir" ; done
        trap -- 'umount root/{dev,proc,sys,var/cache/apt} ; trap - RETURN' RETURN
        chroot root /usr/bin/apt update
        chroot root /usr/bin/apt --assume-yes upgrade --with-new-pkgs
        chroot root /usr/bin/apt --assume-yes install "${packages[@]}" "$@"

        dpkg-query --show > packages-buildroot.txt
        dpkg-query --admindir=root/var/lib/dpkg --show > packages.txt
}

function distro_tweaks() {
        rm -fr root/etc/kernel root/etc/rc.d

        # The default policy does not differentiate root's home directory.
        test -s root/usr/lib/systemd/system/root.mount &&
        sed -i -e s/admin_home/user_home_dir/g root/usr/lib/systemd/system/root.mount

        # Default to the nftables firewall interface if it was installed.
        local cmd ; for cmd in iptables ip6tables
        do
                test -x "root/usr/sbin/$cmd-nft" &&
                chroot root /usr/bin/update-alternatives --set "$cmd" "/usr/sbin/$cmd-nft"
        done

        # Allow NetworkManager to manage devices and DNS.
        rm -f root/usr/lib/NetworkManager/conf.d/10-{dns-resolved,globally-managed-devices}.conf

        test -s root/usr/lib/systemd/system/console-setup.service &&
        ln -fst root/usr/lib/systemd/system/multi-user.target.wants ../console-setup.service

        test -s root/usr/share/systemd/tmp.mount &&
        mv -t root/usr/lib/systemd/system root/usr/share/systemd/tmp.mount

        test -s root/etc/default/useradd &&
        sed -i -e '/^SHELL=/s,=.*,=/bin/bash,' root/etc/default/useradd

        test -s root/etc/inputrc &&
        sed -i -e '/history-search/s/^[# ]*//' root/etc/inputrc

        opt double_display_scale &&
        test -s root/etc/default/console-setup &&
        sed -i -e '/^FONTSIZE="/s/"8x16"/"16x32"/' root/etc/default/console-setup

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
        sed '/<svg/s/"22"/"480"/g' /usr/share/icons/ubuntu-mono-dark/apps/22/distributor-logo.svg > /root/logo.svg &&
        convert -background none /root/logo.svg logo.bmp
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
        $cat << EOF > "$buildroot/etc/dracut.conf.d/99-settings.conf"
add_drivers+=" ${options[ramdisk]:+loop} "
compress="zstd --threads=0 --ultra -22"
hostonly="no"
i18n_install_all="no"
reproducible="yes"
EOF

        # Load disk support before verity so dm-init can find the partition.
        if opt rootmod
        then
                $mkdir -p "$buildroot/usr/lib/modprobe.d"
                echo > "$buildroot/usr/lib/modprobe.d/verity-root.conf" \
                    "softdep dm-verity pre: ${options[rootmod]}"
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

# Override the default SELinux policy mapping to use this distro's default.
eval "$(declare -f validate_options | $sed s/=targeted/=default/)"

# Override relabeling to fix pthread_cancel and broken QEMU display behavior.
eval "$(declare -f relabel | $sed \
    -e '/ldd/iopt squash && cp -t "$root/lib" /usr/lib/*/libgcc_s.so.1' \
    -e 's/qemu-system-[^ ]* /&-display none /g')"

# Override default OVMF paths for this distro's packaging.
eval "$(declare -f set_uefi_variables | $sed \
    -e 's,/usr/\S*VARS\S*.fd,/usr/share/OVMF/OVMF_VARS_4M.fd,' \
    -e 's,/usr/\S*CODE\S*.fd,/usr/share/OVMF/OVMF_CODE_4M.secboot.fd,' \
    -e 's,/usr/\S*/\(Shell\|EnrollDefaultKeys\).efi,,g')"

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import
        $gpg --verify "$2" "$1"
        [[ $($sha256sum "$3") == $($sed -n "s/ .*-$(archmap)-root.tar.xz$//p" "$1")\ * ]]
} << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBEqwKTUBEAC8V01JGfeYVVlwlcr0dmwF8n+We/lbxwArjR/gZlH7/MJEZnAL
QHUrDTpD3SkfbsjQgeNt8eS3Jyzoc2r3t2nos4rXPH4kIzAvtqslz6Ns4ZYjoHVk
VC2oV8vYbxER+3/lDjTWVII7omtDVvqH33QlqYZ8+bQbs21lZb2ROJIQCiH0Yzaq
YR0I2SEykBL873V0ygdyW/mCMwniXTLUyGAUV4/28NOzw/6LGvJElJe4UqwQxl/a
XtPIJjPka8LA8+nDi5/u6WEgDWgBhLEHvQG1BNdttm3WCjbu4zS3mNfNBidTamZf
OaMJUZVYxhOB5kNQqyR4eYqFK/U+305eLrZ05ocadsmcQWkHQVbgt+g4yyFNl56N
5AirkFjVtfArkUJfINGgJ7gkSeyqTJK24f33vsIpPwRQ5eFn7H4PwGc0Piym73YL
JnlR94LNEG0ceOJ7u1r+WuaesIj+lKIZsG/rRLf7besaMCCtPcimVgEAmBoIdpTp
dP3aa54w/dvfSwW47mGY14G5PBk/0MDy2Y5HOeXat3RXpGZZFh7zbwSQ93RhYH3b
NPNd5lMu3ZRkYX19FWxoLCi5lx4K3flYhiolZ5i4KxJCoGRobsKjm74Xv2QlvCXY
yAk5BnAQCsu5hKZ1sOhQADCcKz1Zbg8JRc3vmelaJ/VFvHTzs4hJTUvOowARAQAB
tDRVRUMgSW1hZ2UgQXV0b21hdGljIFNpZ25pbmcgS2V5IDxjZGltYWdlQHVidW50
dS5jb20+iQI3BBMBAgAhAhsDAh4BAheABQJKsColBQsJCAcDBRUKCQgLBRYCAwEA
AAoJEBpdbEx9uHyBLicP/jXjfLhs255oT8gmvBXS9WDGSdpPiaMxd0CHEyHuT/Xd
WsoUUYXAPAti8Fyk2K99mze+n4SLCRRJhxqYlcpVy2icc41/VkKI9d/pF4t54RM5
TledYpKVV7xTgoUHZpuL2mWzaT61MzRAxUqqaU42/xSLxLt/noryPHo57IghJXbA
cmgLhFT0fZmtDy9cD4IBvurZF6cRuMJXjxZmssntMHsFZl4PEC3oR/WgJA37OrjM
Vej9r+JA909vr5K/UO+P2gWYOH/2CnGDlaTu72wUrLf6QV5jMyKc6+G7fw5bTJd9
lE8Km2H+4z9e+t7IOv9oxojvESu27exD4LU7SjzZloYnmlTCsdHwgSJVnf+lqXoZ
eUNT9Tmku8VzwCoExTwo9exaJUHeO8ABkfsJVmry40ovzQAHh427+6NpxgkWErVo
cnm54LPIQucZYJrg08s/azRzCjlsYChsaWMvGlMZQo52MuLvETHVPtSggP7sLeIO
lS+8tO1ykSJY65j8AHYBV6hb9EOjWmqpx33GXn8AyCPiMs9/pmeOI0V6YMm6HCLA
wZb+rRS6gcyt9dlWyLU0QLlpmwHSOVJMv2rnNCUtz6pb8y/o9AN2Z48RpH9C9cfv
4dAfbtYn7uTd+M3gk4xyURREg2xuDnraYFs6cZ60/bSy63GxTyi/cCc0S57GgtOK
=KgX0
-----END PGP PUBLIC KEY BLOCK-----
EOF

function archmap() case ${*:-$DEFAULT_ARCH} in
    aarch64)  echo arm64 ;;
    i[3-6]86) echo i386 ;;
    x86_64)   echo amd64 ;;
    *) return 1 ;;
esac

function releasemap() case ${*:-${options[release]:-$DEFAULT_RELEASE}} in
    23.10) echo mantic ;;
    23.04) echo lunar ;;
    22.10) echo kinetic ;;
    22.04) echo jammy ;;
    21.10) echo impish ;;
    21.04) echo hirsute ;;
    20.10) echo groovy ;;
    20.04) echo focal ;;
    *) return 1 ;;
esac

# OPTIONAL (IMAGE)

function enable_repo_ppa() {
        local -r repo=${1?Missing PPA name}
        local -r url=https://ppa.launchpadcontent.net/$repo/ppa/ubuntu/
        mkdir -p root/etc/apt/{sources.list,trusted.gpg}.d
        sed 'p;s/^deb/# &-src/' <<< "deb $url $(releasemap) main" \
            > "root/etc/apt/sources.list.d/$repo.list"
        gpg --dearmor > "root/etc/apt/trusted.gpg.d/$repo.gpg"
}

# WORKAROUNDS

# Older Ubuntu releases are still available, but most of them are EOL.
[[ ${options[release]:-$DEFAULT_RELEASE} > 22.04 ]] ||
. "legacy/${options[distro]}22.04.sh"
