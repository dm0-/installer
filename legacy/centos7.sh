# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=centos [release]=7).

packages=()
packages_buildroot=()

DEFAULT_RELEASE=7
options[secureboot]=
options[uefi]=

function create_buildroot() {
#       local -r image="https://github.com/CentOS/sig-cloud-instance-images/raw/CentOS-${options[release]:=$DEFAULT_RELEASE}-$DEFAULT_ARCH/docker/centos-${options[release]}-$DEFAULT_ARCH-docker.tar.xz"
        local -r image="https://github.com/CentOS/sig-cloud-instance-images/raw/$(archmap_container)/docker/centos-${options[release]:=$DEFAULT_RELEASE}-${DEFAULT_ARCH/#i[4-6]86/i386}-docker.tar.xz"

        opt bootable && packages_buildroot+=(kernel microcode_ctl)
        opt gpt && opt uefi && packages_buildroot+=(dosfstools mtools)
        opt secureboot && packages_buildroot+=(pesign)
        opt selinux && packages_buildroot+=(kernel policycoreutils qemu-kvm)
        opt squash && packages_buildroot+=(squashfs-tools)
        opt uefi && packages_buildroot+=(centos-logos ImageMagick)
        opt verity && packages_buildroot+=(veritysetup)
        packages_buildroot+=(e2fsprogs openssl)

        $mkdir -p "$buildroot"
        $curl -L "$image" > "$output/image.tar.xz"
#       $curl -L "$image.asc" | verify_distro - "$output/image.tar.xz"
        verify_distro "$output/image.tar.xz"
        $tar -C "$buildroot" -xJf "$output/image.tar.xz"
        $rm -f "$output/image.tar.xz"

        # Let the configuration decide if the system should have documentation.
        $sed -i -e '/^tsflags=/d' "$buildroot/etc/yum.conf"

        configure_initrd_generation
        initialize_buildroot "$@"

        enter /usr/bin/yum --assumeyes --setopt=tsflags=nodocs upgrade
        enter /usr/bin/yum --assumeyes --setopt=tsflags=nodocs \
            install "${packages_buildroot[@]}"
}

function install_packages() {
        opt bootable && packages+=(systemd)
        opt networkd && packages+=(systemd-networkd systemd-resolved)
        opt selinux && packages+=(selinux-policy-targeted)

        mount -o bind,x-mount.mkdir {,root}/var/cache/yum
        trap -- 'umount root/var/cache/yum ; trap - RETURN' RETURN

        opt arch && mkdir -p root/etc/yum/vars &&
        echo "${options[arch]/#i[4-6]86/i386}" > root/etc/yum/vars/basearch
        yum --assumeyes --installroot="$PWD/root" \
            --releasever="${options[release]}" \
            install "${packages[@]:-filesystem}" "$@"

        rpm -qa | sort > packages-buildroot.txt
        rpm --root="$PWD/root" -qa | sort > packages.txt
}

function distro_tweaks() {
        rm -fr root/etc/chkconfig.d root/etc/init{.d,tab} root/etc/rc{.d,.local,[0-6].d}

        mkdir -p root/usr/lib/systemd/system/local-fs.target.wants
        ln -fst root/usr/lib/systemd/system/local-fs.target.wants ../tmp.mount

        mkdir -p root/usr/lib/systemd/system/systemd-journal-catalog-update.service.d
        echo > root/usr/lib/systemd/system/systemd-journal-catalog-update.service.d/tmpfiles.conf \
            -e '[Unit]\nAfter=systemd-tmpfiles-setup.service'

        test -x root/usr/libexec/upowerd &&
        echo 'd /var/lib/upower' > root/usr/lib/tmpfiles.d/upower.conf

        sed -i -e 's/^[^#]*PS1="./&\\$? /;s/mask 002$/mask 022/' root/etc/bashrc
}

function save_boot_files() if opt bootable
then
        opt uefi && test ! -s logo.bmp && convert -background none /usr/share/centos-logos/fedora_logo_darkbackground.svg -color-matrix '0 1 0 0 0 0 1 0 0 0 0 1 1 0 0 0' logo.bmp
        test -s initrd.img || build_systemd_ramdisk /boot/initramfs-*
        test -s vmlinuz || cp -p /boot/vmlinuz-* vmlinuz
fi

# Override ext4 file system handling to work with old CentOS 7 command options.
eval "$(
declare -f mount_root | $sed 's/ount -o X-mount.mkdir /kdir -p root ; mount /'
declare -f unmount_root | $sed 's/tune2fs -O read-only/: &/'
)"

# Override the SELinux labeling VM to add more old CentOS 7 kernel modules.
eval "$(declare -f relabel | $sed 's, /[^ ]*/vmlinuz , /boot/vmlinuz-* ,
s/\(-name \)\?sd_mod\(.ko.xz -o\)\?/\1crct10dif_common\2 \1crc-t10dif\2 &/')"

# Override verity formatting to skip ancient broken bash syntax.
eval "$(declare -f verity | $sed 's/"[^ ]*#opt_params.*"/0/')"

# Override initrd creation to work with old CentOS 7 command options.
eval "$(declare -f build_systemd_ramdisk relabel squash |
$sed 's/cpio -D \([^ ]*\) \([^|]*\)|/{ cd \1 ; cpio \2 ; } |/')"

# Override the /etc overlay to disable persistent Git support.
eval "$(declare -f overlay_etc | $sed 's/test.*git/false/')"

# Override initrd configuration to add device mapper support when needed.
eval "$(declare -f configure_initrd_generation | $sed /sysroot.mount/r<(echo \
    "echo 'add_dracutmodules+=\" dm \"'" \
    '>> "$buildroot/etc/dracut.conf.d/99-settings.conf"'))"

# OPTIONAL (BUILDROOT)

function enable_repo_epel() {
        local -r key="RPM-GPG-KEY-EPEL-${options[release]}"
        local -r url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-${options[release]}.noarch.rpm"
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script << EOF
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFKuaIQBEAC1UphXwMqCAarPUH/ZsOFslabeTVO2pDk5YnO96f+rgZB7xArB
OSeQk7B90iqSJ85/c72OAn4OXYvT63gfCeXpJs5M7emXkPsNQWWSju99lW+AqSNm
jYWhmRlLRGl0OO7gIwj776dIXvcMNFlzSPj00N2xAqjMbjlnV2n2abAE5gq6VpqP
vFXVyfrVa/ualogDVmf6h2t4Rdpifq8qTHsHFU3xpCz+T6/dGWKGQ42ZQfTaLnDM
jToAsmY0AyevkIbX6iZVtzGvanYpPcWW4X0RDPcpqfFNZk643xI4lsZ+Y2Er9Yu5
S/8x0ly+tmmIokaE0wwbdUu740YTZjCesroYWiRg5zuQ2xfKxJoV5E+Eh+tYwGDJ
n6HfWhRgnudRRwvuJ45ztYVtKulKw8QQpd2STWrcQQDJaRWmnMooX/PATTjCBExB
9dkz38Druvk7IkHMtsIqlkAOQMdsX1d3Tov6BE2XDjIG0zFxLduJGbVwc/6rIc95
T055j36Ez0HrjxdpTGOOHxRqMK5m9flFbaxxtDnS7w77WqzW7HjFrD0VeTx2vnjj
GqchHEQpfDpFOzb8LTFhgYidyRNUflQY35WLOzLNV+pV3eQ3Jg11UFwelSNLqfQf
uFRGc+zcwkNjHh5yPvm9odR1BIfqJ6sKGPGbtPNXo7ERMRypWyRz0zi0twARAQAB
tChGZWRvcmEgRVBFTCAoNykgPGVwZWxAZmVkb3JhcHJvamVjdC5vcmc+iQI4BBMB
AgAiBQJSrmiEAhsPBgsJCAcDAgYVCAIJCgsEFgIDAQIeAQIXgAAKCRBqL66iNSxk
5cfGD/4spqpsTjtDM7qpytKLHKruZtvuWiqt5RfvT9ww9GUUFMZ4ZZGX4nUXg49q
ixDLayWR8ddG/s5kyOi3C0uX/6inzaYyRg+Bh70brqKUK14F1BrrPi29eaKfG+Gu
MFtXdBG2a7OtPmw3yuKmq9Epv6B0mP6E5KSdvSRSqJWtGcA6wRS/wDzXJENHp5re
9Ism3CYydpy0GLRA5wo4fPB5uLdUhLEUDvh2KK//fMjja3o0L+SNz8N0aDZyn5Ax
CU9RB3EHcTecFgoy5umRj99BZrebR1NO+4gBrivIfdvD4fJNfNBHXwhSH9ACGCNv
HnXVjHQF9iHWApKkRIeh8Fr2n5dtfJEF7SEX8GbX7FbsWo29kXMrVgNqHNyDnfAB
VoPubgQdtJZJkVZAkaHrMu8AytwT62Q4eNqmJI1aWbZQNI5jWYqc6RKuCK6/F99q
thFT9gJO17+yRuL6Uv2/vgzVR1RGdwVLKwlUjGPAjYflpCQwWMAASxiv9uPyYPHc
ErSrbRG0wjIfAR3vus1OSOx3xZHZpXFfmQTsDP7zVROLzV98R3JwFAxJ4/xqeON4
vCPFU6OsT3lWQ8w7il5ohY95wmujfr6lk89kEzJdOTzcn7DBbUru33CQMGKZ3Evt
RjsC7FDbL017qxS+ZVA/HGkyfiu4cpgV8VUnbql5eAZ+1Ll6Dw==
=hdPa
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$url" > epel.rpm
rpm --checksig epel.rpm
rpm --install epel.rpm
exec rm -f epel.rpm
EOF
}

function enable_repo_rpmfusion() {
        local key="RPM-GPG-KEY-rpmfusion-free-el-${options[release]}"
        local url="https://download1.rpmfusion.org/free/el/updates/${options[release]}/$DEFAULT_ARCH/r/rpmfusion-free-release-${options[release]}-4.noarch.rpm"
        enable_repo_epel
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script << EOF
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFVE8DcBEACmsFjnapHXm5l0dXbyxXZU8sZVawRIQ/lG9Yc9tSICcY8QuSxu
636wsVHiQHd0sIipk6vvgWfTTV+w0OxyovY8PFciEtOC4JZBJO1cT952sDxRTzcU
Y+DArqPUwqyMqJo86BxwoQi9qdg4eNlp5RNamzbu2yKpPZUk4RWF0QnlEJ5bQ8xY
Q2HyzR6YUsKBuCbNV/OevxxSjSFesWqmE2zIFVDsNvS+FGbH6SwDrKgBeDHCeg35
KQgHyNkONoe7EjfCVdWwWsOdo9pqEKZKd4U6Sz234d9JqvF7y3+Lc85l/TxU+G/C
uXxRki5XVx3sMH0UgK0nn0fBEv95Dtq5I7EWNYDOesFDbBRjhqo5dh51yOcfn1QO
ATKGwo2WZTGc32kOXwu/zzZaT37HulyOpJ/8jAoOQ6qH5T7RDy2M1vlAvGcdy2dz
GUyD2bNlPSp1exw6CWOXjty/9nOglJBBsr/YwTundSKpZSKPkn3z74ZAD4Pqviwx
yRsk1UjHlCm8sPfahkpRheFKDJT/wIBUhI7tbzyfxMaNwryc1U+yOiAl92sMr8ra
a0CGk48cFa6vulSq/ELdt/qF+I0TywacaTvU3ySSd3Juff54c8ELNBjTGY4MAomk
y1P755q83yBdYaRDU6U1ljKP1GP8Kgilk6QCWu1izFPepPK4Bi7ZGTUEhQARAQAB
tE5SUE0gRnVzaW9uIGZyZWUgcmVwb3NpdG9yeSBmb3IgRUwgKDcpIDxycG1mdXNp
b24tYnVpbGRzeXNAbGlzdHMucnBtZnVzaW9uLm9yZz6JAjIEEwECABwFAlVE8DcC
GwMECwkIBwMVCAoDFgIAAh4BAheAAAoJEHWLPRj1z2weGigQAKO+ULRBzztGDg3m
ev8rDEOfv49x3T4+tTYlMOtvsg8Jvi5okGp+bXO0qZkw8463Ljrs5FAW1/oIGFYA
D9RMDnlgpDAhP6Gho/tGIPc6yfSHOUm2uS5Ve1Q7j3eBHr8IlAvpg/1U9IIS7LDU
WcVNjpsBzog8pGXRBSYx5yi7ddP5GcQPLwn0TT7jkawzrlmfnMz3un6gaxgFIxmS
wzd+lr7CHP3Lptxt3Oe5pliEQ58kuBzt0gkxGkkbeRyolareanJBlIozYIM3TQum
K4UbXIjPWlHr02z+qtrkpkDgM5aO+rEPGctd4W12zT5Gqp5Ij5fuFUHgFKvxf+0F
t7RDWffAiKtk8HX0PoytIBY9fiQtZXjnbPq1rT65brz6bc85HR3sRx2+gn9IN+Cg
OwdV7NoL8Dj7w3J5DMS1yT1KbmwRHHyKD0muL3NUw9RZXPmmUakbIvLZlERKhyca
JZlkakLUOvesXcZg2Zqug36ET0AQO/Af7e6dw8jXBc4BN/R5U8LU0ENaB3apRcdF
NEDqxPo98MGzIxqJUjWkwJfRvdqAPEM8JLeyhcuChsmwIGF0WbLsmVJ90LJxsoZQ
G+iQKiFwF8HO6fBk4APSAtic+j+9uHoLMS9tWsLABmNQCvjtRe6hxz20yud672uo
OEGWGYNPKeu56Dbc18pxBHez9m42
=buWg
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
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFVE8KwBEADAINLGFvBAfBPErA7/zzsGyNgKB1tuyuJVeANZdCxYrWp3G2k0
bwllSkuyBIDLauLzerWsRfNTSW7nAu818G2nfBrX8xUPwCSeECJwUneW0FO72hZ9
NsUXOGC5UShrEcWmjku2ZqsJmDtikUyY6wMsLTiUyooMtwleGu26+nrXKrr7MxAJ
PjNOXwJ1g7LK55Wucv7uhUtRN7ioGUwG24i2pyp9zJ8ElVO8c0BbcfDHYarjYNME
kzalY6N+UQCur5OLkJwI195pqie2TjpyvpG0A+noWpRBV8j6dwrI3fmO2AtAQZdt
39t4AMNoEGiaxClOqeOGPU1zju2cP5EXbCGMKj1pbmvzUdoxknvZJus38s3SjndK
KL9SRwr4e3VOaCZWEDsBQNQvqC3RnPpGbFZksAv6VtgZAzHX1UrYdtxEhWQ+ZXaV
MSbsgJa8ph2dhG1vK6X2z46/zNHU//ESFwmu/jjHWJP2pOEM20yjo3GHX1uBKmuJ
hci2573ZJJubxGf4hSUTylu1lNZ5+SWczQPxyirTZqYwuYV9kdX1kANQ7xCi/2J9
1yOsTyANWlofkCzr4x+sDDjyK5zL9jkleXbKmO+g6nRDIpCvDXCODMT5nfi/+/qY
2FqcwQawhDdKh/U6OQ0N6FM4hhmPTqgtDINnn/m+k1viYv1b0RJcjo+/OwARAQAB
tFFSUE0gRnVzaW9uIG5vbmZyZWUgcmVwb3NpdG9yeSBmb3IgRUwgKDcpIDxycG1m
dXNpb24tYnVpbGRzeXNAbGlzdHMucnBtZnVzaW9uLm9yZz6JAjIEEwECABwFAlVE
8KwCGwMECwkIBwMVCAoDFgIAAh4BAheAAAoJEMj3bfGjEI9sreUP+wXzGVNm5f4v
SsqLGGlGlNIfhtLBBzEX47cbl5qwiT1YoajV6R5ccUeH0oh85Q6sQQ+1VzlTghzi
XdR7HF5HEt3CXLfSIwqlQGjDiwpA8RaohZ3XUmGIsCo+/RhUc2r87MWqXhf1YdEi
0KfI40WQXHPqy+RBbnLHRKHvSY8z/x4aa1jOOfOl/kLo6xjtjtB8su17at9+WPro
fAJOXzM11XYNLDpP3zj8zmY46Fhji03u4URom8AWmxKMebzzv+zCLvjlOodvHjuB
7OQT7uZBjM1DT1saqy0XuANSQNv/ylnhhQ8vnbZxL0IzPWMxGOZjjnY5/ZLLNlmJ
+6qbXLWFM+WeYidM9+yUKK7jLDufGOKvsJMbQug2dgbs9Nkj5aTRQfRBv5szwRoi
xKhyyar9tJp1WjnKcmh9lVMuXqrQ4C7LEJp9SiDhdjXNojKjnwlKHSSKgQ8iBIF6
1rMOc4IaaGSJpWMuCRHPckZPwxxeeRiAYOH3MUbe2eJZZnQLVJH5IahokjMgOGFi
kOvnMlvsXRWbp0NBtRDBrtk2+w/pbqnOCbEKPBKdupeo2M4Zc2EE8arxiswRT4G+
StgWlrhjmlGJbTkngGK4cHrf5cwgEDNdM60io4EVRJ9B3LcjJdFMIC0Ep4/28+vw
LMOlOqkf/TTZWb3HXsWQgLt6zIWSi6pS
=h3MJ
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

# Override the tmpfiles leaf quota group since CentOS 7 systemd is too old.
eval "$(declare -f store_home_on_var | $sed 's/Q /d /')"

# WORKAROUNDS

# CentOS container releases are horribly broken.  Pin them to static versions.
function archmap_container() case "$DEFAULT_ARCH" in
    aarch64)  echo 02ea5808a8a155bad28677dd5857c8d382027e14 ;;
    i[3-6]86) echo 206003c215684a869a686cf9ea5f9697e577c546 ;;
    ppc64le)  echo a8e4f3da8300d18da4c0e5256d64763965e66810 ;;
    x86_64)   echo b2d195220e1c5b181427c3172829c23ab9cd27eb ;;
    *) return 1 ;;
esac

# CentOS container releases are horribly broken.  Check sums with no signature.
function verify_distro() [[
        x$($sha256sum "$1" | $sed -n '1s/ .*//p') = x$(case "$DEFAULT_ARCH" in
            aarch64)  echo 6db9d6b9c8122e9fe7e7fc422e630ee10ff8b671ea5c8f7f16017b9b1c012f67 ;;
            i[3-6]86) echo 5aba6af141b5c1c5218011470da2e75a9d93a0fff5b62a30cc277945cd12ba2b ;;
            ppc64le)  echo cc60b971d00aa3c57e0fc913de8317bcc74201af9bdbd8f5c85eedbd29b93abc ;;
            x86_64)   echo 2b66ff1fa661f55d02a8e95597903008d55e0f98da8f65e3f47c04ac400f9b35 ;;
        esac)
]]

# CentOS 7 is too old to provide sysusers, so just pretend it always works.
function systemd-sysusers() { : ; }
