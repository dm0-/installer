packages=(sys-apps/baselayout sys-libs/glibc)
packages_buildroot=()

DEFAULT_ARCH=$($uname -m)
DEFAULT_PROFILE=17.1
DEFAULT_RELEASE=20190908T214502Z
options[arch]=$DEFAULT_ARCH
options[profile]=$DEFAULT_PROFILE
options[release]=$DEFAULT_RELEASE

function create_buildroot() {
        local -A archmap=([x86_64]=amd64)
        local -a packages=()
        local -r arch="${archmap[$DEFAULT_ARCH]:-amd64}"
        local profile="default/linux/$arch/${options[profile]:=$DEFAULT_PROFILE}/no-multilib/hardened"
        local stage3="https://gentoo.osuosl.org/releases/$arch/autobuilds/${options[release]:=$DEFAULT_RELEASE}/hardened/stage3-$arch-hardened+nomultilib-${options[release]}.tar.xz"

        opt bootable && packages+=(sys-kernel/gentoo-sources virtual/udev)
        opt selinux && packages+=(sec-policy/selinux-base-policy) && profile+=/selinux && stage3=${stage3/+/-selinux+}
        opt squash && packages+=(sys-fs/squashfs-tools)
        opt verity && packages+=(sys-fs/cryptsetup)
        opt uefi && packages+=(media-gfx/imagemagick x11-themes/gentoo-artwork)
        test "x${options[arch]:=$DEFAULT_ARCH}" = "x$DEFAULT_ARCH" || packages+=(sys-devel/crossdev)

        $mkdir -p "$buildroot"
        $curl -L "$stage3.DIGESTS.asc" > "$output/digests"
        $curl -L "$stage3" > "$output/stage3.tar.xz"
        verify_gentoo "$output/digests" "$output/stage3.tar.xz"
        $tar -C "$buildroot" -xJf "$output/stage3.tar.xz"
        $rm -f "$output/digests" "$output/stage3.tar.xz"

        enter /bin/bash -euxo pipefail << EOF
ln -fns /var/db/repos/gentoo/profiles/$profile /etc/portage/make.profile
mkdir -p /etc/portage/{package.{accept_keywords,unmask,use},profile,repos.conf}
cat <(echo) - << 'EOG' >> /etc/portage/make.conf
FEATURES="\$FEATURES -selinux"
PYTHON_TARGETS="\$PYTHON_SINGLE_TARGET"
EOG
echo systemd >> /etc/portage/profile/use.force
echo -e 'sslv2\nsslv3\nstatic-libs\n-systemd' >> /etc/portage/profile/use.mask

# Support SELinux with systemd.
echo -e 'sys-apps/gentoo-systemd-integration\nsys-apps/systemd' >> /etc/portage/package.unmask/systemd.conf

# Support zstd squashfs compression.
echo '~sys-fs/squashfs-tools-4.4 ~amd64' >> /etc/portage/package.accept_keywords/squashfs-tools.conf
echo 'sys-fs/squashfs-tools zstd' >> /etc/portage/package.use/squashfs-tools.conf

emerge-webrsync
emerge --jobs=4 -1v ${packages[*]} ${packages_buildroot[*]} $*

if test -x /usr/bin/crossdev
then
        cat << 'EOG' > /etc/portage/repos.conf/crossdev.conf
[crossdev]
location = /var/db/repos/crossdev
EOG
        crossdev --stable --target ${options[arch]}-pc-linux-gnu
fi

mkdir -p "/build/${options[arch]}/etc"
cp -at "/build/${options[arch]}/etc" /etc/portage
cd "/build/${options[arch]}/etc/portage"
echo split-usr >> profile/use.mask
EOF
}

function install_packages() {
        local -rx {PORTAGE_CONFIG,,SYS}ROOT="/build/${options[arch]}"
        local -rx PKGDIR="$ROOT/var/cache/binpkgs"

        opt bootable && packages+=(sys-apps/systemd)
        opt iptables && packages+=(net-firewall/iptables)
        opt selinux && packages+=(sec-policy/selinux-base-policy)

        # Cheat bootstrapping
        mv "$ROOT"/etc/portage/profile/use.force{,.save}
        echo -e '-selinux\n-systemd' > "$ROOT"/etc/portage/profile/use.force
        USE='-* kill' emerge --jobs=4 -1v sys-apps/util-linux
        mv "$ROOT"/etc/portage/profile/use.force{.save,}
        packages+=(sys-apps/util-linux)

        emerge --jobs=4 -1bv "${packages[@]}" "$@"
        emerge --{,sys}root=root --jobs=$(nproc) -1Kv "${packages[@]}" "$@"
        mkdir -p root/{dev,proc,sys}

        qlist -CIRSSUv > packages-buildroot.txt
        qlist --root=/ -CIRSSUv > packages-host.txt
        qlist --root=root -CIRSSUv > packages.txt
}

function save_boot_files() {
        opt uefi && convert -background none /usr/share/pixmaps/gentoo/1280x1024/LarryCowBlack1280x1024.png -crop 380x324+900+700 -trim -transparent black logo.bmp
        :
}

function distro_tweaks() { : ; }

function relabel() { : ; }

function verify_gentoo() {
        local -rx GNUPGHOME="$output/gnupg"
        trap "$rm -fr $GNUPGHOME" RETURN
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
