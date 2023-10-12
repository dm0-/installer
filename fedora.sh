# SPDX-License-Identifier: GPL-3.0-or-later
packages_buildroot=()

options[loadpin]=

DEFAULT_RELEASE=38

function create_buildroot() {
        local -r cver=1.6
        local -r image="https://dl.fedoraproject.org/pub/fedora/linux/releases/${options[release]:=$DEFAULT_RELEASE}/Container/$DEFAULT_ARCH/images/Fedora-Container-Base-${options[release]}-$cver.$DEFAULT_ARCH.tar.xz"

        opt bootable && packages_buildroot+=(kernel-core zstd)
        opt bootable && [[ ${options[arch]:-$DEFAULT_ARCH} == *[3-6x]86* ]] && packages_buildroot+=(linux-firmware microcode_ctl)
        opt bootable && opt squash && packages_buildroot+=(kernel-modules)
        opt gpt && packages_buildroot+=(util-linux)
        opt gpt && opt uefi && packages_buildroot+=(dosfstools mtools)
        opt read_only || packages_buildroot+=(findutils)
        opt read_only && ! opt squash && packages_buildroot+=(erofs-utils)
        opt secureboot && packages_buildroot+=(nss-tools pesign)
        opt selinux && packages_buildroot+=(busybox kernel-core policycoreutils qemu-system-x86-core zstd)
        opt squash && packages_buildroot+=(squashfs-tools)
        opt uefi && packages_buildroot+=(binutils fedora-logos ImageMagick systemd-boot-unsigned)
        opt uefi_vars && packages_buildroot+=(qemu-system-x86-core)
        opt verity && packages_buildroot+=(veritysetup)
        opt verity_sig && opt bootable && packages_buildroot+=(kernel-devel keyutils)
        packages_buildroot+=(e2fsprogs openssl systemd)

        $curl -L "${image%-Base*}-${options[release]}-$cver-$DEFAULT_ARCH-CHECKSUM" > "$output/checksum"
        $curl -L "$image" > "$output/image.txz"
        verify_distro "$output/checksum" "$output/image.txz"
        $tar -xJOf "$output/image.txz" '*/layer.tar' | $tar -C "$buildroot" -x
        $rm -f "$output/checksum" "$output/image.txz"

        # Disable bad packaging options.
        $sed -i -e '/^[[]main]/ainstall_weak_deps=False' "$buildroot/etc/dnf/dnf.conf"
        $sed -i -e 's/^enabled=1.*/enabled=0/' "$buildroot"/etc/yum.repos.d/*{cisco,modular}*.repo

        # Let the configuration decide if the system should have documentation.
        $sed -i -e '/^tsflags=/d' "$buildroot/etc/dnf/dnf.conf"

        configure_initrd_generation
        initialize_buildroot "$@"

        script "${packages_buildroot[@]}" << 'EOF'
dnf --assumeyes --setopt=tsflags=nodocs upgrade
exec dnf --assumeyes --setopt=tsflags=nodocs install "$@"
EOF
}

function install_packages() {
        opt bootable && packages+=(systemd)
        opt networkd && packages+=(systemd-networkd systemd-resolved)
        opt selinux && packages+=("selinux-policy-${options[selinux]}")

        mount -o bind,X-mount.mkdir {,root}/var/cache/dnf
        trap -- 'umount root/var/cache/dnf ; trap - RETURN' RETURN

        dnf --assumeyes --installroot="$PWD/root" \
            ${options[arch]:+--forcearch="${options[arch]}"} \
            --releasever="${options[release]}" \
            install "${packages[@]:-filesystem}" "$@"

        # Fix PAM and friends immediately before any configuration is written.
        if [[ -x root/usr/bin/authselect ]]
        then
                chroot root /usr/bin/authselect select minimal --force --nobackup
                chroot root /usr/bin/authselect opt-out
        fi

        rpm -qa | sort > packages-buildroot.txt
        rpm --root="$PWD/root" -qa | sort > packages.txt
}

function distro_tweaks() {
        exclude_paths+=('usr/lib/.build-id')

        rm -fr root/etc/inittab root/etc/rc.d

        test -x root/usr/bin/update-crypto-policies &&
        chroot root /usr/bin/update-crypto-policies --no-reload --set FUTURE

        test -s root/etc/dnf/dnf.conf &&
        sed -i -e '/^[[]main]/ainstall_weak_deps=False' root/etc/dnf/dnf.conf

        compgen -G 'root/etc/yum.repos.d/*cisco*.repo' &&
        sed -i -e 's/^enabled=1.*/enabled=0/' root/etc/yum.repos.d/*{cisco,modular}*.repo

        sed -i -e 's/^[^#]*PS1="./&\\$? /;s/mask 002$/mask 022/' root/etc/bashrc
}

function save_boot_files() if opt bootable
then
        opt uefi && test ! -s logo.bmp &&
        magick -background none /usr/share/fedora-logos/fedora_logo.svg -trim logo.bmp
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

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import
        $gpg --verify "$1"
        [[ $($sha256sum "$2") == $($sed -n '/=/{s/.* //p;q;}' "$1")\ * ]]
} << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGIC2cYBEADJye1aE0AR17qwj6wsHWlCQlcihmqkL8s4gbOk1IevBbH4iXJx
lu6bN+NhTcCCX6eHmaL5Pwb/bpkMmLR+/r1D2cLDK24YzvN6kJnwRQUTf2dbqYmg
mNBgIMm+kAabBZPwUHUzyQ9CT/WJpYr1OYu8JIkdxF35nrPewnnOUUqxqbi8fXRQ
gskSLF8UveiOjFIqmWwlPwT1UtnevAaF80UGQlkwFvqjjh4b9vKY2gHMAQwt+wg5
HFFCSwSrnd88ZoDb3pKvDMeurYUiPzF5f2r+ziVkMuaSNckvp58uge7HvyqQPAdJ
ZRswCCxhUAo9VqkNfB4Ud25ASyalk9jOE3HB8E35gFfPXvuX1n15THXNcwMEiybk
Omne2YwXL8ShGNr5otjqywThMrrqcl2g/pJVTcpDHTR5Hn9YRp+GHlYLjyEr+/x7
xM19y9ca9GUiJqDbEREHcKKIhYiGmcIjjcJvei/3C/aM4pqeGFJBbVSnw3qeMxH/
6ArAMA1sAdShCkv2YjlcF0r4uoCjXdS3xrKLz9PSCquot7RySnOE9TZ7flfJll7Z
q+lNaSeJg7FK8VWSUb9Lit6VEYVbzWKzespDDbujrHbFpydyq8gXurk7bSR2w0te
gsmytQqT/w1z2bydgGF6SfY9Px0wuA8GQKr48l5Bhdc6+vHHFqPKzz0PVQARAQAB
tDFGZWRvcmEgKDM4KSA8ZmVkb3JhLTM4LXByaW1hcnlAZmVkb3JhcHJvamVjdC5v
cmc+iQJOBBMBCAA4FiEEalG7q7o9VGe2FxIhgJqNfOsQtGQFAmIC2cYCGw8FCwkI
BwIGFQoJCAsCBBYCAwECHgECF4AACgkQgJqNfOsQtGScyw/7BLmD4Fwi4QZY94zl
vlJdNufZRavOemSIVVDHoCr8pQBAdrvoMypxJd5zM4ODIqFsjdYpFti+Tkeq4/4U
25UoLPEOtU8UDt2uq7LqfdCxspaj7VyXAJIkpf7wEvLS4Jzo+YaMIlsd0dCrMXTM
vhu4gKpBFW6C+gGlmuDyTJbyrf7ilytgVzVtIfRrT7XffylviIlZHwKm43UDjvzX
YEl3EAFR1RjATwXMy2aJh7GCNsz+fKs+7YRKQUhpMF5un/2pyNJO+LbVGGwGZvga
K9Kfsg/4r1ync4nDDD1dadKIHhobDeiJ9uZLoBvvVDz7Ywu7q/vv4zIPxstYBNq4
6fLKDtYXuJCK0EV9Qy4ox67t0UGlaRGH8y5YUqOI10xH7iQej0xWlSc8w2dKhPz8
z9XLv2OMK+PvqvflhFHhWkqEoQRqTu0TVD0fLLe4lqieJlqZcJqW0F9G/vNSSWmf
POLa/Nim71gL2fPjCJOIRV4K/cJSyBmu5NchG7dHD5sUtJxZ4TFSuepaBZ8cPK1x
e26TaCBqoUWgUXWmw+P89aOpYOJYEFfT/VAm2Ywn+c1EFUmD+30wQ7aP/RUFl94z
n0BjqsWDnCKVFHydZ0TZSpeADmXMg2VYZPcp/cQR1KjoBoDxAscis7b1XPQUg7CB
zquq5jBVAnsNIhs7g47GWKyDUJM=
=aCLl
-----END PGP PUBLIC KEY BLOCK-----
EOF

# OPTIONAL (BUILDROOT)

function enable_repo_rpmfusion_free() {
        local key="RPM-GPG-KEY-rpmfusion-free-fedora-${options[release]}"
        local url="https://download1.rpmfusion.org/free/fedora/releases/${options[release]}/Everything/$DEFAULT_ARCH/os/Packages/r/rpmfusion-free-release-${options[release]}-1.noarch.rpm"
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script "$url"
} << 'EOF'
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
curl -L "$1" > rpmfusion-free.rpm
curl -L "${1/-release-/-release-tainted-}" > rpmfusion-free-tainted.rpm
rpm --checksig --define=_pkgverify_{'flags 0x0','level all'} rpmfusion-free{,-tainted}.rpm
rpm --install rpmfusion-free{,-tainted}.rpm
exec rm -f rpmfusion-free{,-tainted}.rpm
EOF

function enable_repo_rpmfusion_nonfree() {
        local key="RPM-GPG-KEY-rpmfusion-nonfree-fedora-${options[release]}"
        local url="https://download1.rpmfusion.org/nonfree/fedora/releases/${options[release]}/Everything/$DEFAULT_ARCH/os/Packages/r/rpmfusion-nonfree-release-${options[release]}-1.noarch.rpm"
        enable_repo_rpmfusion_free
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script "$url"
} << 'EOF'
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
curl -L "$1" > rpmfusion-nonfree.rpm
curl -L "${1/-release-/-release-tainted-}" > rpmfusion-nonfree-tainted.rpm
rpm --checksig --define=_pkgverify_{'flags 0x0','level all'} rpmfusion-nonfree{,-tainted}.rpm
rpm --install rpmfusion-nonfree{,-tainted}.rpm
exec rm -f rpmfusion-nonfree{,-tainted}.rpm
EOF

# OPTIONAL (IMAGE)

function check_for_updates() if test -x root/usr/bin/dnf
then
        # Define a service to categorize which updates are available, if any.
        cat << 'EOF' > root/usr/lib/systemd/system/image-update-check.service
[Unit]
Description=Write the MOTD with the system update status
After=network.target network-online.target
#Before=display-manager.service sshd.service  # Don't delay booting.
[Service]
ExecStart=/bin/bash -eo pipefail -c 'declare -A total=() ; \
for retry in 1 2 3 4 5 ; do while read -rs count type extra ; \
do [[ $$count =~ [0-9]+ ]] && total[$$type]=$$count || \
{ [[ $$count == Error: ]] && break ; } ; \
done < <(exec /usr/bin/dnf --quiet updateinfo summary --available 2>&1) ; \
[[ -n $$count ]] && /usr/bin/sleep 10 || break ; done ; \
[[ -n $$count ]] && exit 1 ; unset "total["{New,Moderate,Low}"]" ; \
/usr/bin/mkdir -pZ /run/motd.d ; exec > /run/motd.d/image-update-check ; \
[[ $${#total[@]} -gt 0 ]] || exit 0 ; \
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
        ln -fst root/usr/lib/systemd/system/multi-user.target.wants \
            ../image-update-check.service

        # Define a timer to check for updates twice per day.
        cat << 'EOF' > root/usr/lib/systemd/system/image-update-check.timer
[Unit]
Description=Check for system update notifications twice daily
[Timer]
AccuracySec=1h
OnUnitInactiveSec=12h
[Install]
WantedBy=timers.target
EOF
        ln -fst root/usr/lib/systemd/system/timers.target.wants \
            ../image-update-check.timer

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
fi

function drop_package() while read -rs
do exclude_paths+=("${REPLY#/}")
done < <(rpm --root="$PWD/root" -qal "$@")

# WORKAROUNDS

# Older Fedora releases are still available, but most of them are EOL.
[[ ${options[release]:-$DEFAULT_RELEASE} -ge DEFAULT_RELEASE ]] ||
[[ ${options[distro]:-fedora} != fedora ]] ||  # Expect CentOS reusing this.
. "legacy/fedora$(( --DEFAULT_RELEASE )).sh"
