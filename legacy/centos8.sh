# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=centos [release]=8).

packages=(glibc-minimal-langpack)

function create_buildroot() {
        local -r image="https://github.com/CentOS/sig-cloud-instance-images/raw/$(archmap_container)/docker/centos-${options[release]:=$DEFAULT_RELEASE}-$DEFAULT_ARCH.tar.xz"

        opt bootable && packages_buildroot+=(kernel-core)
        opt bootable && [[ ${options[arch]:-$DEFAULT_ARCH} == *[3-6x]86* ]] && packages_buildroot+=(microcode_ctl)
        opt bootable && opt squash && packages_buildroot+=(kernel-modules)
        opt gpt && opt uefi && packages_buildroot+=(dosfstools mtools)
        opt secureboot && packages_buildroot+=(pesign)
        opt selinux && packages_buildroot+=(kernel-core policycoreutils qemu-kvm-core)
        opt squash && packages_buildroot+=(squashfs-tools)
        opt uefi && packages_buildroot+=(centos-logos ImageMagick)
        opt uefi_vars && packages_buildroot+=(dosfstools mtools qemu-kvm-core)
        opt verity && packages_buildroot+=(veritysetup)
        packages_buildroot+=(crypto-policies-scripts e2fsprogs openssl)

        $curl -L "$image" > "$output/image.txz"
        verify_distro "$output"/image.txz{.asc,}
        $tar -C "$buildroot" -xJf "$output/image.txz"
        $rm -f "$output"/image.txz{.asc,}

        # Disable bad packaging options.
        $sed -i -e '/^[[]main]/ainstall_weak_deps=False' "$buildroot/etc/dnf/dnf.conf"

        # Let the configuration decide if the system should have documentation.
        $sed -i -e '/^tsflags=/d' "$buildroot/etc/dnf/dnf.conf"

        # Rewrite repositories to use the archive of the last CentOS release.
        $sed -i \
            -e 's/^mirrorlist=/#&/' \
            -e 's,^#*\(baseurl=http://\)mirror,\1vault,' \
            "$buildroot"/etc/yum.repos.d/CentOS-*.repo

        configure_initrd_generation
        initialize_buildroot "$@"

        opt networkd || opt uefi && enable_repo_epel  # EPEL now has core RPMs.
        script "${packages_buildroot[@]}" << 'EOF'
dnf --assumeyes --setopt=tsflags=nodocs upgrade
exec dnf --assumeyes --setopt=tsflags=nodocs install "$@"
EOF
}

# Override package installation to fix modules.
eval "$(declare -f install_packages | $sed -e 's/ systemd-resolved//' \
    -e '/{ *$/amkdir -p root/etc ; cp -pt root/etc /etc/os-release')"

function distro_tweaks() {
        exclude_paths+=('usr/lib/.build-id')

        rm -fr root/etc/chkconfig.d root/etc/init{.d,tab} root/etc/rc{.d,.local,[0-6].d}

        mkdir -p root/usr/lib/systemd/system/local-fs.target.wants
        ln -fst root/usr/lib/systemd/system/local-fs.target.wants ../tmp.mount

        mkdir -p root/usr/lib/systemd/system/systemd-journal-catalog-update.service.d
        echo > root/usr/lib/systemd/system/systemd-journal-catalog-update.service.d/tmpfiles.conf \
            -e '[Unit]\nAfter=systemd-tmpfiles-setup.service'

        [[ -x root/usr/libexec/upowerd ]] &&
        echo 'd /var/lib/upower' > root/usr/lib/tmpfiles.d/upower.conf

        [[ -d root/etc/crypto-policies ]] &&
        base_dir=$PWD/root/etc/crypto-policies \
        profile_dir=$PWD/root/usr/share/crypto-policies \
        update-crypto-policies --no-reload --set FUTURE

        [[ -s root/etc/dnf/dnf.conf ]] &&
        sed -i -e '/^[[]main]/ainstall_weak_deps=False' root/etc/dnf/dnf.conf

        [[ -s root/etc/locale.conf ]] ||
        echo LANG=C.UTF-8 > root/etc/locale.conf

        sed -i -e 's/^[^#]*PS1="./&\\$? /;s/mask 002$/mask 022/' root/etc/bashrc
}

# Override the UEFI logo source to use the old distro name.
eval "$(declare -f save_boot_files | $sed s/centos/redhat/)"

# Override image generation to drop EROFS support since the kernel is too old.
eval "$(
declare -f create_root_image {,un}mount_root | $sed \
    -e '/if\|size/s/read_only/squash/' \
    -e 's/! opt ramdisk/{ opt verity || & ; }/'
declare -f relabel | $sed s/read_only/squash/
declare -f squash | $sed '/!/s/read_only/squash/'
declare -f kernel_cmdline | $sed /type=erofs/d
)"

# Override SELinux initrd/squashfs creation to remove zstd and add old modules.
eval "$(declare -f relabel | $sed '
s/\(-name \)\?sd_mod\(.ko.xz -o\)\?/\1t10-pi\2 &/
s/zstd.*-22/xz --check=crc32 -9e/;s/zstd.* 22/xz/')"

# Override squashfs creation since CentOS 8 doesn't support zstd.
eval "$(declare -f squash | $sed 's/ zstd .* 22 / xz /')"

# Override ramdisk creation since the kernel is too old to support zstd.
eval "$(declare -f configure_initrd_generation | $sed /compress=/d)"
eval "$(declare -f squash build_systemd_ramdisk | $sed \
    -e 's/zstd --[^|>]*/xz --check=crc32 -9e /')"

# Override ESP creation to support old dosfstools that can't use offsets.
eval "$(declare -f partition | $sed '/^ *if opt uefi/,/^ *fi/{
/esp_image=/s/=.*/=esp.img ; truncate --size=$(( esp * bs )) $esp_image/
s/ --offset=[^ ]* / /;s/ gpt.img / $esp_image /
/^ *fi/idd bs=$bs conv=notrunc if=$esp_image of=gpt.img seek=$start
}')"

# Override UEFI variable generation to use the old QEMU bare SMBIOS argument.
eval "$(declare -f set_uefi_variables | $sed -e '/timeout/i\
cat <(echo -en "\\x0B\\x05\\x34\\x12\\x01") "$keydir/sb.oem" <(echo -en "\\0\\0") > "$keydir/sb.smbios"
s/type=11,path\(=\S*\)oem/file\1smbios/')"

# Map supported architectures to the final CentOS 8 container image commits.
function archmap_container() case $DEFAULT_ARCH in
    aarch64) echo e79ccf67325a31bf0bb79a8a0e82d3d8a4de2da8 ;;
    ppc64le) echo 76f876b31bb82108a1acf2cee1032c1d2ebc3bd9 ;;
    x86_64)  echo 607af70702bacc6f46fab2ded055ab23d9113831 ;;
    *) return 1 ;;
esac

# The last CentOS 8 containers had no signatures, so check their sums directly.
function verify_distro() [[
        $($sha256sum "$2") == $(case $DEFAULT_ARCH in
            aarch64) echo 5beedefae3fcb64fa1e05d2facece2c764748791275e2d03f5be3518c7fd6429 ;;
            ppc64le) echo 01afd6f91e7e97e9ce1e137ddec2d665c70aec9398facec1d7eb92f1da7985fe ;;
            x86_64)  echo 6cc70032cb92991d1d916e8e77c2f3f6aedeacf0ba524af93bfac89c0a2438d9 ;;
        esac)\ *
]]

# OPTIONAL (BUILDROOT)

function enable_repo_epel() {
        local -r key="RPM-GPG-KEY-EPEL-${options[release]}"
        local -r url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-${options[release]}.noarch.rpm"
        $sed -i -e '/^[[]powertools]$/,/^$/s/^enabled=.*/enabled=1/' "$buildroot/etc/yum.repos.d/CentOS-Linux-PowerTools.repo"
        [[ -s $buildroot/etc/pki/rpm-gpg/$key ]] || script "$url"
} << 'EOF'
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFz3zvsBEADJOIIWllGudxnpvJnkxQz2CtoWI7godVnoclrdl83kVjqSQp+2
dgxuG5mUiADUfYHaRQzxKw8efuQnwxzU9kZ70ngCxtmbQWGmUmfSThiapOz00018
+eo5MFabd2vdiGo1y+51m2sRDpN8qdCaqXko65cyMuLXrojJHIuvRA/x7iqOrRfy
a8x3OxC4PEgl5pgDnP8pVK0lLYncDEQCN76D9ubhZQWhISF/zJI+e806V71hzfyL
/Mt3mQm/li+lRKU25Usk9dWaf4NH/wZHMIPAkVJ4uD4H/uS49wqWnyiTYGT7hUbi
ecF7crhLCmlRzvJR8mkRP6/4T/F3tNDPWZeDNEDVFUkTFHNU6/h2+O398MNY/fOh
yKaNK3nnE0g6QJ1dOH31lXHARlpFOtWt3VmZU0JnWLeYdvap4Eff9qTWZJhI7Cq0
Wm8DgLUpXgNlkmquvE7P2W5EAr2E5AqKQoDbfw/GiWdRvHWKeNGMRLnGI3QuoX3U
pAlXD7v13VdZxNydvpeypbf/AfRyrHRKhkUj3cU1pYkM3DNZE77C5JUe6/0nxbt4
ETUZBTgLgYJGP8c7PbkVnO6I/KgL1jw+7MW6Az8Ox+RXZLyGMVmbW/TMc8haJfKL
MoUo3TVk8nPiUhoOC0/kI7j9ilFrBxBU5dUtF4ITAWc8xnG6jJs/IsvRpQARAQAB
tChGZWRvcmEgRVBFTCAoOCkgPGVwZWxAZmVkb3JhcHJvamVjdC5vcmc+iQI4BBMB
AgAiBQJc9877AhsPBgsJCAcDAgYVCAIJCgsEFgIDAQIeAQIXgAAKCRAh6kWrL4bW
oWagD/4xnLWws34GByVDQkjprk0fX7Iyhpm/U7BsIHKspHLL+Y46vAAGY/9vMvdE
0fcr9Ek2Zp7zE1RWmSCzzzUgTG6BFoTG1H4Fho/7Z8BXK/jybowXSZfqXnTOfhSF
alwDdwlSJvfYNV9MbyvbxN8qZRU1z7PEWZrIzFDDToFRk0R71zHpnPTNIJ5/YXTw
NqU9OxII8hMQj4ufF11040AJQZ7br3rzerlyBOB+Jd1zSPVrAPpeMyJppWFHSDAI
WK6x+am13VIInXtqB/Cz4GBHLFK5d2/IYspVw47Solj8jiFEtnAq6+1Aq5WH3iB4
bE2e6z00DSF93frwOyWN7WmPIoc2QsNRJhgfJC+isGQAwwq8xAbHEBeuyMG8GZjz
xohg0H4bOSEujVLTjH1xbAG4DnhWO/1VXLX+LXELycO8ZQTcjj/4AQKuo4wvMPrv
9A169oETG+VwQlNd74VBPGCvhnzwGXNbTK/KH1+WRH0YSb+41flB3NKhMSU6dGI0
SGtIxDSHhVVNmx2/6XiT9U/znrZsG5Kw8nIbbFz+9MGUUWgJMsd1Zl9R8gz7V9fp
n7L7y5LhJ8HOCMsY/Z7/7HUs+t/A1MI4g7Q5g5UuSZdgi0zxukiWuCkLeAiAP4y7
zKK4OjJ644NDcWCHa36znwVmkz3ixL8Q0auR15Oqq2BjR/fyog==
=84m8
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$1" > epel.rpm
rpm --checksig --define=_pkgverify_{'flags 0x0','level all'} epel.rpm
rpm --install epel.rpm
exec rm -f epel.rpm
EOF

function enable_repo_rpmfusion_free() {
        local key="RPM-GPG-KEY-rpmfusion-free-el-${options[release]}"
        local url="https://download1.rpmfusion.org/free/el/updates/${options[release]}/$DEFAULT_ARCH/r/rpmfusion-free-release-${options[release]}-0.1.noarch.rpm"
        enable_repo_epel
        [[ -s $buildroot/etc/pki/rpm-gpg/$key ]] || script "$url"
} << 'EOF'
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFwzh0wBEADfwWMombl8hSzfzeWwGEyBXs4S+9YYmxgtFjnCzR4aUIXxevvf
tY8YWWEeaIosG/V+XJuw+EjcKCDk0RpFimBIyO6IjwkJTVmFVYuzVc/O3fs64Hbl
Dm1fMpOrnVUJnV59nUhDkcnYdysMPKuBJghw+a85FlhnlDlnVC94XPcD5QyTfjpR
bfvCSCFSTobIHUoOI7SK7r7x+qldQeopnCQILZyhaeXDW+jFC1E50oaUtw2sMvfF
q0d03f8yZsiJm2sVpPJ/zEJG8yXogJyEsfMXDoxn7sA8mP09W3cScci/fE7tIUu+
3HXzAn8CqZRCxIp2uDvpeom7e8NqwIorWZDiP7IhdQr1sf4bud07buCdovmHRSjE
+IuW9gTFAHVFdL3dEwzOMKkdV3i6ru4VVjPm4K4SEbFHaKDrwJy+RlVmcPdH99HI
aHqj5GU140D4grp814hkciy2EXiJP6qMqi8thAQof3ljr4ZZB3/g9tOl/zE865Xp
RvmKS7qv45Vr6wCYvoquaAvm3wusUgQL3TWlAhfGqys13ijqmJIwz75YbL8J9hma
biwLHl4xrWe5quNXdUsC/ijThKbl8duUWYw4nBN1azcVZHV2bZMgnxOsZp3zN0lU
RB1K7U4kEni8c11PGHsL7uH/OuSy3Wq7WPpX7J5nrMbJMmqL3s5jyUkhVQARAQAB
tE5SUE0gRnVzaW9uIGZyZWUgcmVwb3NpdG9yeSBmb3IgRUwgKDgpIDxycG1mdXNp
b24tYnVpbGRzeXNAbGlzdHMucnBtZnVzaW9uLm9yZz6JAkUEEwEIAC8WIQSDeTXN
GeEjqn+KjmmXnwxpFYs4EQUCXDOHTAIbAwQLCQgHAxUICgIeAQIXgAAKCRCXnwxp
FYs4EVdWEADfHIbm/1o6Pf/KRU4SYLFm45AnDQ4OKCEH8y8SvvPJQMKZYnXfiblt
XYK1ec6F4obgl2eNKZoIrKS6CBwu3NpvjWXCPBn/rkiksB7pbDid6j0veHrZmrnG
6Ngo2VnGIjLcDRPcAn/WjzpevS8X9q6AF9bZoQ8BSoxCAoGueko1R02iWtZPlV1P
IQEW2cF9HQdI1vw0Nh+ohiDO87/mNyVUdjootpncVnArlf5MGj8Ut9zo6yJSlxG0
7lvMnreH4OeIaJPGYRHhsFtSfe7HbPaCmYAmlCFLmw3AhHuEnYSCAt2kMVxlUrAc
li/FxEyXAKS/C2OYk3jDA215K/G14tBWDkNLwyULiURDH6lvWyRqyOVzr198AJLK
3WK6G5RfngV82VyW0SX4XScnQxuk55HsMC8CKapmPtdjDjqR1qrKDe6umNskwPII
tCU7ZZL+8Do/eMHqJgUBS5II+bSngVSfO4Yz/zeU0WWZhDirh9C3CeZ3kEVSLQq/
eC9Zt2/x8xykXXKeswg5I0m0+FBAo9w2ChXyi9rQSFEScqCqml+7elQZTF/TrsHC
Os+yoXdCv3hm0wFMdQl4PeXrzmZOB/kMC+XIESoRpRVBod2C6EzHKYCXzoY9iqla
RmIw/1lMM/XnE/x+XQzvkcOQPHSxQ+iJjD5arhoROh2wCvfb3IPnYw==
=Fpo1
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$1" > rpmfusion-free.rpm
curl -L "${1/-release-/-release-tainted-}" > rpmfusion-free-tainted.rpm
rpm --checksig --define=_pkgverify_{'flags 0x0','level all'} rpmfusion-free{,-tainted}.rpm
rpm --install rpmfusion-free{,-tainted}.rpm
exec rm -f rpmfusion-free{,-tainted}.rpm
EOF

function enable_repo_rpmfusion_nonfree() {
        local key="RPM-GPG-KEY-rpmfusion-nonfree-el-${options[release]}"
        local url="https://download1.rpmfusion.org/nonfree/el/updates/${options[release]}/$DEFAULT_ARCH/r/rpmfusion-nonfree-release-${options[release]}-0.1.noarch.rpm"
        enable_repo_rpmfusion_free
        [[ -s $buildroot/etc/pki/rpm-gpg/$key ]] || script "$url"
} << 'EOF'
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFwzh1YBEAC7Ar5IGGne3Vm7nPLQjHB32NAlqRWNsnAfpyquGuRFeL3X/83k
FxaLX4wTBc/fqtRC+HRPaKxDNPlI9TOTyYnn8F96v8grOPB8joy9mbDIsekK4uAc
tec36/++mV00yiKiS8cPQKgkAr7oZTqgz4LXV8z/ROUwOKQqi68YjL1WvEzVEZ0B
QBo5TSiYhGP1qMTHuH6PN3n+MBCDTWBAj2WxK9i/ga3NgcsJIqnXEgmKg9NoL9qq
ZMTynrayGbaaqoPgF1vOmegQNa3/3xy3kF7Ax1bofy9l44sWYi0Dge5yYnsJrdZ7
PYVSXghbWYNolZ1BS4tyXwQb+DfOq3vgfo+82eHK7RiM0KaJAfFzCIFxNe45ihAR
Mn8xSICN3RMiF+1uY6VNUXFZQVbxsmqEnBfXqBMWlM1aBjntpzf7+MzothmaEg67
oSGG154vmyCnzwgeCWnptua+SUoZhXiHW3OtiwBtz6pP1xPVibKXeoLmP+wQ+rBA
gnAw/Qpnpx/xz906cl/5soKNzbKxIjh904+/1FYFWh4OcBwxVNtk9OcM7nBO+6u3
CPhGav09YEByE9RR/MkM9FUK8oqkxXDfD2NPgZJ/wTvvanGbHNJDDa+jh97rajNs
OANp61jtNZv5i7ocNjkPl8Yh4UxmUW+TDWPqoBpXSAjT1Xis3h5sM9wJjwARAQAB
tFFSUE0gRnVzaW9uIG5vbmZyZWUgcmVwb3NpdG9yeSBmb3IgRUwgKDgpIDxycG1m
dXNpb24tYnVpbGRzeXNAbGlzdHMucnBtZnVzaW9uLm9yZz6JAkUEEwEIAC8WIQTP
n9WfYdZhIUbNrI4UtnktvdqEdQUCXDOHVgIbAwQLCQgHAxUICgIeAQIXgAAKCRAU
tnktvdqEdVZKD/9WOrxPq/cXRPlWxSxPPIe4FTo88HmOPwE1cbFwoq7e7zLoUkDS
efiD9m4szxYHUeGXvp0gkh6/FLDkvMQnlHoJviVDYK3sPAudqAOl2KtZlWE4SykD
mNjONZMcPXBtceGmur1ZiqSFiidBkDS8Z316dhfxAJqtiVZFL1iUuaIZVX2vYcJc
zvDJe4JVeZQ9lYxpvnwcmPOoe4M7eJlniKNK5tsBHa4daI2iIehIsVoz1CY4VO5N
C3rfAOUs8wDKJEKRFe30nPhPgzojA9uhD++cOymhnbxLQBQnS6mHlGJ7hYMI8YaJ
P21G8pRcYmyZbC/fbeB+91dR+uGeZ8qKPRO4/EnPCcbBkrlVawCmh1QXThx1Mwrt
j56J3ppZm15zMkf8PsXOj3VXQSHAPLwPATE0vmh+EAbEydBg41bv+e3SCkpaYsjC
egrXACGnoCL2wdXPxsJUCmUWWSkCGKmYbCMq2Rod+FqZ48igxh3V4v7kVSFThkML
fdF04ENL9r5PUdfM8JCW8KlXvkSjMROUxTzVyuyMd9Ct7FkUDIryBXufGKQ9jyA6
FPYwBme26R8Vu3hI9VCFgO1e0rVFyvDuiBnJZ0atXqkn9vnXkA2zVfabb0PN5Pn/
dHObVLLxbTYoPqQl+lCZtfyyELWx13EYkn4VkG+y0D79aC7sxwEeZX1n5w==
=WjVe
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$1" > rpmfusion-nonfree.rpm
curl -L "${1/-release-/-release-tainted-}" > rpmfusion-nonfree-tainted.rpm
rpm --checksig --define=_pkgverify_{'flags 0x0','level all'} rpmfusion-nonfree{,-tainted}.rpm
rpm --install rpmfusion-nonfree{,-tainted}.rpm
exec rm -f rpmfusion-nonfree{,-tainted}.rpm
EOF

[[ options[release] -ge DEFAULT_RELEASE ]] ||
. "legacy/${options[distro]}$(( --DEFAULT_RELEASE )).sh"
