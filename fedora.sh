# SPDX-License-Identifier: GPL-3.0-or-later
packages=(glibc-minimal-langpack)
packages_buildroot=()

DEFAULT_RELEASE=34

function create_buildroot() {
        local -r cver=1.2
        local -r image="https://dl.fedoraproject.org/pub/fedora/linux/releases/${options[release]:=$DEFAULT_RELEASE}/Container/$DEFAULT_ARCH/images/Fedora-Container-Base-${options[release]}-$cver.$DEFAULT_ARCH.tar.xz"

        opt bootable && packages_buildroot+=(kernel-core microcode_ctl zstd)
        opt bootable && opt squash && packages_buildroot+=(kernel-modules)
        opt gpt && opt uefi && packages_buildroot+=(dosfstools mtools)
        opt read_only || packages_buildroot+=(findutils)
        opt read_only && ! opt squash && packages_buildroot+=(erofs-utils)
        opt secureboot && packages_buildroot+=(nss-tools pesign)
        opt selinux && packages_buildroot+=(busybox kernel-core policycoreutils qemu-system-x86-core zstd)
        opt squash && packages_buildroot+=(squashfs-tools)
        opt uefi && packages_buildroot+=(binutils fedora-logos ImageMagick)
        opt verity && packages_buildroot+=(veritysetup)
        opt verity_sig && opt bootable && packages_buildroot+=(kernel-devel keyutils)
        packages_buildroot+=(e2fsprogs openssl systemd)

        $mkdir -p "$buildroot"
        $curl -L "${image%-Base*}-${options[release]}-$cver-$DEFAULT_ARCH-CHECKSUM" > "$output/checksum"
        $curl -L "$image" > "$output/image.tar.xz"
        verify_distro "$output/checksum" "$output/image.tar.xz"
        $tar -xJOf "$output/image.tar.xz" '*/layer.tar' | $tar -C "$buildroot" -x
        $rm -f "$output/checksum" "$output/image.tar.xz"

        # Disable bad packaging options.
        $sed -i -e '/^[[]main]/ainstall_weak_deps=False' "$buildroot/etc/dnf/dnf.conf"
        $sed -i -e 's/^enabled=1.*/enabled=0/' "$buildroot"/etc/yum.repos.d/*modular*.repo

        # Let the configuration decide if the system should have documentation.
        $sed -i -e '/^tsflags=/d' "$buildroot/etc/dnf/dnf.conf"

        configure_initrd_generation
        initialize_buildroot "$@"

        $cp -a "$buildroot"/etc/resolv.conf{,.orig}
        enter /usr/bin/dnf --assumeyes --setopt=tsflags=nodocs upgrade
        enter /usr/bin/dnf --assumeyes --setopt=tsflags=nodocs \
            install "${packages_buildroot[@]}"
        $rm -f "$buildroot"/etc/resolv.conf
        $cp -a "$buildroot"/etc/resolv.conf{.orig,}
}

function install_packages() {
        opt bootable && packages+=(systemd)
        opt networkd && packages+=(systemd-networkd)
        opt selinux && packages+=(selinux-policy-targeted)

        mount -o bind,X-mount.mkdir {,root}/var/cache/dnf
        trap -- 'umount root/var/cache/dnf ; trap - RETURN' RETURN

        dnf --assumeyes --installroot="$PWD/root" \
            ${options[arch]:+--forcearch="${options[arch]}"} \
            --releasever="${options[release]}" \
            install "${packages[@]:-filesystem}" "$@"

        rpm -qa | sort > packages-buildroot.txt
        rpm --root="$PWD/root" -qa | sort > packages.txt
}

function distro_tweaks() {
        exclude_paths+=('usr/lib/.build-id')

        rm -fr root/etc/inittab root/etc/rc.d

        test -x root/usr/bin/update-crypto-policies &&
        chroot root /usr/bin/update-crypto-policies --set FUTURE

        test -s root/etc/dnf/dnf.conf &&
        sed -i -e '/^[[]main]/ainstall_weak_deps=False' root/etc/dnf/dnf.conf

        compgen -G 'root/etc/yum.repos.d/*modular*.repo' &&
        sed -i -e 's/^enabled=1.*/enabled=0/' root/etc/yum.repos.d/*modular*.repo

        sed -i -e 's/^[^#]*PS1="./&\\$? /;s/mask 002$/mask 022/' root/etc/bashrc
}

function save_boot_files() if opt bootable
then
        opt uefi && test ! -s logo.bmp &&
        sed '/id="g524[17]"/,/\//{/</,/>/d;}' /usr/share/fedora-logos/fedora_logo.svg > /root/logo.svg &&
        convert -background none /root/logo.svg -trim -color-matrix '0 1 0 0 0 0 1 0 0 0 0 1 1 0 0 0' logo.bmp
        test -s initrd.img || build_systemd_ramdisk "$(cd /lib/modules ; compgen -G '[0-9]*')"
        test -s vmlinuz || cp -pt . /lib/modules/*/vmlinuz
        if opt verity_sig
        then
                local -r v=$(echo /lib/modules/[0-9]*)
                "$v/build/scripts/extract-vmlinux" "$v/vmlinuz" > vmlinux
                "$v/build/scripts/insert-sys-cert" -b vmlinux -c "$keydir/verity.der" -s "$v/System.map"
        fi
fi

function configure_initrd_generation() if opt bootable
then
        # Don't expect that the build system is the target system.
        $mkdir -p "$buildroot/etc/dracut.conf.d"
        $cat << 'EOF' > "$buildroot/etc/dracut.conf.d/99-settings.conf"
compress="zstd --threads=0 --ultra -22"
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

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBF8sAZIBEADKYvLg/5FdLXcVryAFd7Q8qrJq23R7ebxUT1u48Dc8xrsfYJZq
aMcna/xw47wZNyek4Z6YpzqfmnjR7H8yRH/1hAPi/ixYnA6DVL7O3eGE5lYGJzN3
E2ILTzBOI9o/pavvtOqW9N5WIus8cqSdA921v8YPzr3/BTKgGqC9biOrMA+3sNoe
U4T+dztLg20SyBTr/rBH0eui2p/ipvIRuJvHLTKTubR+yG804yupI69M6qFBDebT
rm+CBmwVyj/DY/92LgvCgYqV/TL5FU4qvtyB6jd8JkEeaz/G7UmDRB5JqzKEu6TB
N3SY7nwLiRpIaXet1TWVW/8UKSB2JvYt1LbZyEO82/QOIXxqvV6h3kuBI21RvURz
VxEjRlvPRGHMZ80OoAQqNPkLnVTcX1eLj2ClbwoXCmXFSm72cCCt1SzcAmlaWh8E
rXSUZfs7XqkBrbphXHZ1e6Vxjt/RyKC5doklfOhbuF8gJ31CPo/kuOjFrHGzOwgi
Llec+GHGMfI/cUOu59qo3W85GHsntvEMk83QLkKjBInEYjZSAajp/lS4QF+SD4pl
Qj6Vc1mMCmci61cXX5CcIl1YxNJZzUfZEZNbUjDajqGzkYJoG9n2yJB0w4OiqsAe
ZCirmUIeDUNeI082epc4RFuV33hByGYY9kRWSyM+aCF6PYVISj4l1o9KcQARAQAB
tDFGZWRvcmEgKDM0KSA8ZmVkb3JhLTM0LXByaW1hcnlAZmVkb3JhcHJvamVjdC5v
cmc+iQJOBBMBCAA4FiEEjFummQvbJuGfKhqAEWGuaUVxmjkFAl8sAZICGw8FCwkI
BwIGFQoJCAsCBBYCAwECHgECF4AACgkQEWGuaUVxmjlVuA//QnMA02tydqwpM7r4
WZ4OvlVqFWHhn3oDaBSwBvn6R1oC0MWbr79nnFDn3tpSkZDUdb7wyArmaF8kG8tI
wit5xD/JAzqRBVa9z2hY3n1SFafU/hp3DwbGIL4vLUv3fRayCgWsGhGp0tZvDC9q
PSvQZ675XpRG4pt/TGJB5gGXw7Jxoae/ffaJeblLLRDlSV/bKJt9sYpdu5InDG2i
yIUHfamtYQtnENKL/bN6w7tU/IEgCHqxPmPRiJ0gTUAi5Yabp1+JHqskE85Hm2QF
xMonX595Ry1yZzCjPGhCPAknJ4BhisXV+E/iV3Jyh8vxbJCo1//ygd1Xz8SkCuu/
I0xPtFcVSIP2ikYpJwR2nwwQlLbQYIGCw/S1LV725oEYm/Z1xQ5zha2hBB+fxSwz
7MHsD2XIHrP8NNwt3ywG3NV/BSSkvSSStGUNcQyGRi3O/x/BEIRtWRxgoNO9o3jE
xtWFq3G5+gKY+wfYz/cTGlsWPDG7Fzx4lNisIGATKtLNqdedl7LASPK93z0XDdnS
kfKF0HrT9rdzIKRu4xWatUVIq/65Gv7nsavdsRAQL/Y0jl6sjjQac/Te5J0fByHY
6tGG1W0UWTd0rzFWitEZI/64/Bs83rGhjJNLqWXItZ5VqLe0TWzuxvRFLfM7oX8r
n5Si4l7NpIJubWPqjPoCoP5lsS8=
=V2FG
-----END PGP PUBLIC KEY BLOCK-----
EOF
        $gpg --verify "$1"
        test x$($sed -n '/=/{s/.* //p;q;}' "$1") = x$($sha256sum "$2" | $sed -n '1s/ .*//p')
}

# OPTIONAL (BUILDROOT)

function enable_rpmfusion() {
        local key="RPM-GPG-KEY-rpmfusion-free-fedora-${options[release]}"
        local url="https://download1.rpmfusion.org/free/fedora/releases/${options[release]}/Everything/$DEFAULT_ARCH/os/Packages/r/rpmfusion-free-release-${options[release]}-1.noarch.rpm"
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script << EOF
cat << 'EOG' > /tmp/key ; rpmkeys --import /tmp/key
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBF2tu8EBEADnI6bmlE7ebLuYSBKJavk7gwX8L2S0lDwtmAFmNcxQ/tAhh5Gx
2RKEneou12pSxav8MvbKOr4IpJLLmuoQMLYkbQRHovgVfDYdtvK9T8tZH51ACtnC
KKr9SucnKhWpDk3/n/djV0I2qSesE6QcJVrh66bT/8nbyIFbbiYLOgE88YAX5Wdj
TkgmYXJ54l1MP/3N64pFlmk6myYCrLh7cibFYLZOW2Xwfq6Go6HOpGn9Cazb+T6m
LALkVPERu2QkcUhMqy/slD5tFFb7DW1gkwnYiu5PKwThW7laZgmw2yAgDV+JccdK
D9ZHALmy9GyQ1ZjDptpa5BObE5vazbuAbSndoIqwaMxCrlqhIYdmqz4m/HJ9BaC0
mRSkT6N9SqytZXFhu5/Ld6+/Ol3b+q28bnV64qQrDH6hgnrRdqCQpm8g7tZFuk5X
JsB/A+EfI2kE6YXqWaGdEx0XcqOv97n6sRZNweOHX3vSM0eLwmM2dpgc7RvMfcqr
73ylZ9CnWVUD6cl+wE8SnGnVVqYau2spZFzKVAcfi/Zwvh6wM7/83XC2mkIHmoFR
OY5aDWFhoFZFgiHHnmDv6kACNmSHb/oYRkvwQ+JhAQu4I9CYw1sxaUDjwtt7a+4I
mBZM8WuvAVLkqnF+MJetiL15/W834HjCNITV03t9593T6Z1Dxpfv4hy7YwARAQAB
tFVSUE0gRnVzaW9uIGZyZWUgcmVwb3NpdG9yeSBmb3IgRmVkb3JhICgyMDIwKSA8
cnBtZnVzaW9uLWJ1aWxkc3lzQGxpc3RzLnJwbWZ1c2lvbi5vcmc+iQJFBBMBCAAv
FiEE6aSRo94keBTn4Gfq4G+OzdZR/y4FAl2tu8ECGwMECwkIBwMVCAoCHgECF4AA
CgkQ4G+OzdZR/y4ZQhAAmF5A4XC9ymd94BFwsbbpCnx2YlfmsZwT1QzBu9njjkH7
MC4THknYe2B/muE5dPu3NseZMzue1Ou4KbMz4wq82731prLRu+iHAxAxJ1qd8whA
QGuRJAg8+YEXKhpwpD/8P/xJo9IRmPxPM+6mQVTlASv34CEIGff1vJr40tNiU53P
PZq9SWD3/uG84PQRmGXetfF2K3NkXqzkvQSM68JZiYR2+wMkoO9f72B7LTBrfkwy
RcFPA7kj65pysB+l2wez03Dh/MyA3LTusd9M6FGiSOUVpQZ+NUFipIisS3vh/Bgp
zMsj1NSsMLjUDcX8stR8GfVgTxSgWwHTNl75XwTZpJOKMoj97kh9zzLwBhZ1W+xo
8s2W7YqVnOUl8rPm7ZbOefGkamNg8bhqcyNIEbHqR5QZVzDBT2AxVcB6jsxSHf5b
sb+KEJff4g6E4fWPA/IYdtJ7DItbVXnkAjqD7ADUh7Xq7pOgfC/4Cledf27x73m+
sdBvKsEBrroAsX/v4z46mQApszkfjTUAXwj2lUT+ujoktJHXqR71jbY0+8JX6Fyw
6ZW0emxR++bt9ksLcsNmjOQP9TmQpi2CW4Z+Ol2tlwtlnKAo6ecx4aacHKg+FYuQ
HTJRq6E6GpCPn1avf1v797RM+3zzw9TYkadfVLIQQ4HYbYzienOgGGporclrtrQ=
=oOVZ
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$url" > rpmfusion-free.rpm
curl -L "${url/-release-/-release-tainted-}" > rpmfusion-free-tainted.rpm
rpm --checksig rpmfusion-free{,-tainted}.rpm
rpm --install rpmfusion-free{,-tainted}.rpm
exec rm -f rpmfusion-free{,-tainted}.rpm
EOF
        test "x$*" = x+nonfree || return 0
        key=${key//free/nonfree}
        url=${url//free/nonfree}
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script << EOF
cat << 'EOG' > /tmp/key ; rpmkeys --import /tmp/key
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBF2tvGQBEAC5Q2ePLZZafOkFhYHpGZdRRBCcCd+aiLATofFV8+FjPuPLL/3R
7fx9RRukL+XKs6K9houj/oYVHmBY7II1mgeRzZHo6KygnM9ph3RKqQDse4TR9+VX
rctsBRikNc7GViSoiPHLRAJeTrlwYRjPHYfF64nFtcPYfPIlGZkEG8mrHbTjkh36
NAlqb3XC0cOSsKQV5f4Wn8fAUepYUkTxA74sVHLSDcBRj3fGfizkiHohy4OjNPij
1VVvfUQXIGYwEDnrd3JF5c2o6B4MfH7h1aN+xG7GJTRswgjQtYUayUOySD5mdZ9u
lUNfPrIAvwyTnc1IvoJUGlf8wSqz8NmjTHykUU+f6Dldb4JKNavnYaVlmDH4HfK+
FVdAD/1pG/6HL94clf/g8LR3sQ0KU/UZJKbDA81n1X04OREfqdjr81U84iyKyb8S
+5nwYuJvxoe+wHg+iHAK0CXYel6V1GR51yka8+sETXyEjGvXksPMQDVPGIDzDfPr
QVijtL3/1Pgkuz1ZvvXmuxD94uV2rBvjKl1NFSWNXId2J+vI5omllGHR3qskOHFa
My9IQkbV4sMoycW/fP5xbwGhVi5q5Gjo7h6J7TIzyMf4gl6PJTp0AFhOZAMA/dXY
nLDnw+qz+iq0B3I14JSLvgCH/uSUEMl5970+COK7wmPTU7I3Hq6PMbzvqQARAQAB
tFhSUE0gRnVzaW9uIG5vbmZyZWUgcmVwb3NpdG9yeSBmb3IgRmVkb3JhICgyMDIw
KSA8cnBtZnVzaW9uLWJ1aWxkc3lzQGxpc3RzLnJwbWZ1c2lvbi5vcmc+iQJFBBMB
CAAvFiEEeb24j5u/c5EP1Albair5YZSEPGUFAl2tvGQCGwMECwkIBwMVCAoCHgEC
F4AACgkQair5YZSEPGW0Ig/+NJf5+KzbRNuFvvGURQI7SYmYtFXkrW4n6rLPWeIV
UHvd/ko74aMVds7hTWeC0cLpjRMSPuwp9xjqb6NvQaqcUK4IwHzlXocait2HzSl+
h2jI3/wSQXqNkvNrgD3rkYZZZ/x7EBBTSTRUpFPq3yHA/BBXbZNEvFsXOmFAy5y+
E5iYnfyjYKHWd0ZwIliWWtK+V5TU54WqHqKF5J2iIDgANkLXiyqx6+LJ6Ng0YfCQ
fO7IMfwtgUt34AfrHWnq0S9BW0hmtPvcYjTtveQKCeGfdMcpRRJsOrvaDDKo1Wmr
IcvGO2VwiF9i19ppghXOSy7q51wTlEqtj3PWYhmJYcRq8Jr1SqjGx73QhUPtsF67
g3vjNEm8PE7pj7vg52BJlzkx6yU+hH5ZNBRM5ll4ZjiX+X7EzKa9so83uszuwoQA
mScTwyyQDNeflnUwiSgZc7PEv1i0BYIHVK7VjmamhOWZRHaaYFCc//gcmu10TJLn
ZCGF2ZDkAdUT6EoWBsT/QCgYSFggrjH9lgKqC5ON8+F5DO1RQe84irgz9jjE9+62
kgQgWZ6F2RZm5/R28DHdAetji50XbnmXgAk/u9u2Hw2bVVJfJ0WpEVcPvA1L86SE
8i8p1fmzljwRazZAksk5Zh2QfaM0jlMYHWbKpbXQcX19Uerm7D9IkciZvDAmgBYV
S6Y=
=rOqq
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$url" > rpmfusion-nonfree.rpm
curl -L "${url/-release-/-release-tainted-}" > rpmfusion-nonfree-tainted.rpm
rpm --checksig rpmfusion-nonfree{,-tainted}.rpm
rpm --install rpmfusion-nonfree{,-tainted}.rpm
exec rm -f rpmfusion-nonfree{,-tainted}.rpm
EOF
}

# OPTIONAL (IMAGE)

function save_rpm_db() {
        opt selinux && echo /usr/lib/rpm-db /var/lib/rpm >> root/etc/selinux/targeted/contexts/files/file_contexts.subs
        mv root/var/lib/rpm root/usr/lib/rpm-db
        echo > root/usr/lib/tmpfiles.d/rpm-db.conf \
            'L /var/lib/rpm - - - - ../../usr/lib/rpm-db'

        # Define a service and timer to check when updates are available.
        test -x root/usr/bin/dnf || return 0
        cat << 'EOF' > root/usr/lib/systemd/system/image-update-check.service
[Unit]
Description=Write the MOTD with the system update status
After=network.target network-online.target
#Before=display-manager.service sshd.service  # Don't delay booting.
[Service]
ExecStart=/bin/bash -eo pipefail -c 'declare -A total=() ; \
for retry in 1 2 3 4 5 ; do while read -rs count type extra ; \
do [[ $$count =~ [0-9]+ ]] && total[$$type]=$$count || \
{ test "x$$count" = xError: && break ; } ; \
done < <(exec /usr/bin/dnf --quiet updateinfo summary --available 2>&1) ; \
test -n "$$count" && /usr/bin/sleep 10 || break ; done ; \
test -n "$$count" && exit 1 ; unset "total["{New,Moderate,Low}"]" ; \
/usr/bin/mkdir -pZ /run/motd.d ; exec > /run/motd.d/image-update-check ; \
test $${#total[@]} -gt 0 || exit 0 ; \
{ (( total[Critical] + total[Important] )) && echo -n UPDATES REQUIRED ; } || \
{ (( total[Security] )) && echo -n Security updates are available ; } || \
{ (( total[Bugfix] )) && echo -n Bug fixes are available ; } || \
echo -n Updates are available ; sec= ; \
(( total[Critical] )) && sec+=" ($${total[Critical]} critical)" ; \
(( total[Important] )) && { sec="$${sec/%?/, }" ; \
sec="${sec:- (}$${total[Important]} important)" ; } ; \
echo -n $${total[Security]:+, $${total[Security]} security$$sec} ; \
echo -n $${total[Bugfix]:+, $${total[Bugfix]} bugfix} ; \
echo -n $${total[Enhancement]:+, $${total[Enhancement]} enhancement} ; \
echo -n $${total[other]:+, $${total[other]} other}'
ExecStartPost=-/bin/bash -euo pipefail -c 'test -x /usr/bin/dconf || exit 0 ; \
test -s /etc/dconf/db/gdm.d/01-banner -a -s /run/motd.d/image-update-check && \
echo -e > /etc/dconf/db/gdm.d/02-banner "[org/gnome/login-screen]\n\
banner-message-text=\'$(</run/motd.d/image-update-check)\'" || \
/usr/bin/rm -f /etc/dconf/db/gdm.d/02-banner ; \
exec /usr/bin/dconf update'
TimeoutStartSec=5m
Type=oneshot
[Install]
WantedBy=multi-user.target
EOF
        cat << 'EOF' > root/usr/lib/systemd/system/image-update-check.timer
[Unit]
Description=Check for system update notifications twice daily
[Timer]
AccuracySec=1h
OnUnitInactiveSec=12h
[Install]
WantedBy=timers.target
EOF

        # Show the status message on GDM if it exists.
        if test -x root/usr/sbin/gdm
        then
                mkdir -p root/etc/dconf/db/gdm.d root/etc/dconf/profile
                cat << 'EOF' > root/etc/dconf/db/gdm.d/01-banner
[org/gnome/login-screen]
banner-message-enable=true
EOF
                cat << 'EOF' > root/etc/dconf/profile/gdm
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
EOF
        fi

        # Only enable the units if explicitly requested.
        if test "x$*" = x+updates
        then
                ln -fst root/usr/lib/systemd/system/timers.target.wants \
                    ../image-update-check.timer
                ln -fst root/usr/lib/systemd/system/multi-user.target.wants \
                    ../image-update-check.service
        fi
}

function drop_package() while read -rs
do exclude_paths+=("${REPLY#/}")
done < <(rpm --root="$PWD/root" -qal "$@")

# WORKAROUNDS

# Older Fedora releases are still available, but most of them are EOL.
[[ ${options[release]:-$DEFAULT_RELEASE} -ge DEFAULT_RELEASE ]] ||
[[ ${options[distro]:-fedora} != fedora ]] ||  # Expect CentOS reusing this.
. "legacy/fedora$(( --DEFAULT_RELEASE )).sh"
