. fedora.sh  # Inherit Fedora's RPM functions.

DEFAULT_RELEASE=8

function create_buildroot() {
        local -r build=8.1.1911-20200113.3
        local -r image="https://github.com/CentOS/sig-cloud-instance-images/raw/CentOS-${build%%-*}-$DEFAULT_ARCH/docker/CentOS-${options[release]:=$DEFAULT_RELEASE}-Container-$build-layer.$DEFAULT_ARCH.tar.xz"

        opt bootable && packages_buildroot+=(kernel-core microcode_ctl)
        opt bootable && opt squash && packages_buildroot+=(kernel-modules)
        opt executable && opt uefi && packages_buildroot+=(dosfstools mtools)
        opt selinux && packages_buildroot+=(kernel-core policycoreutils qemu-kvm-core)
        opt squash && packages_buildroot+=(squashfs-tools)
        opt verity && packages_buildroot+=(veritysetup)
        opt uefi && packages_buildroot+=(centos-logos ImageMagick) &&
        opt sb_cert && opt sb_key && packages_buildroot+=(openssl pesign)
        packages_buildroot+=(e2fsprogs)

        $mkdir -p "$buildroot"
        $curl -L "$image" > "$output/image.tar.xz"
        $curl -L "$image.asc" | verify_distro - "$output/image.tar.xz"
        $tar -C "$buildroot" -xJf "$output/image.tar.xz"
        $rm -f "$output/image.tar.xz"

        # Disable bad packaging options.
        $sed -i -e '/^[[]main]/ainstall_weak_deps=False' "$buildroot/etc/dnf/dnf.conf"

        configure_initrd_generation
        initialize_buildroot

        opt networkd || opt uefi && enable_epel  # EPEL now carries core RPMs.
        enter /usr/bin/dnf --assumeyes upgrade
        enter /usr/bin/dnf --assumeyes install "${packages_buildroot[@]}" "$@"
}

# Override package installation to fix modules and the networkd RPM name.
eval "$(declare -f install_packages | $sed \
    -e '/{ *$/amkdir -p root/etc ; cp -pt root/etc /etc/os-release' \
    -e '/networkd/iopt networkd && packages+=(systemd-networkd)')"

function distro_tweaks() {
        exclude_paths+=('usr/lib/.build-id')

        rm -fr root/etc/chkconfig.d root/etc/init{.d,tab} root/etc/rc{.d,.local,[0-6].d}

        mkdir -p root/usr/lib/systemd/system/local-fs.target.wants
        ln -fst root/usr/lib/systemd/system/local-fs.target.wants ../tmp.mount

        mkdir -p root/usr/lib/systemd/system/systemd-journal-catalog-update.service.d
        echo > root/usr/lib/systemd/system/systemd-journal-catalog-update.service.d/tmpfiles.conf \
            -e '[Unit]\nAfter=systemd-tmpfiles-setup.service'

        test -x root/usr/libexec/upowerd &&
        echo 'd /var/lib/upower' > root/usr/lib/tmpfiles.d/upower.conf

        test -x root/usr/bin/update-crypto-policies &&
        chroot root /usr/bin/update-crypto-policies --set FUTURE

        test -s root/etc/dnf/dnf.conf &&
        sed -i -e '/^[[]main]/ainstall_weak_deps=False' root/etc/dnf/dnf.conf

        sed -i -e 's/^[^#]*PS1="./&\\$? /;s/mask 002$/mask 022/' root/etc/bashrc
}

function save_boot_files() if opt bootable
then
        test -s vmlinuz || cp -pt . /lib/modules/*/vmlinuz
        test -s initrd.img || cp -p /boot/*/*/initrd initrd.img
        opt selinux && test ! -s vmlinuz.relabel && ln -fn vmlinuz vmlinuz.relabel
        opt uefi && test ! -s logo.bmp && convert -background none /usr/share/redhat-logos/fedora_logo_darkbackground.svg -color-matrix '0 1 0 0 0 0 1 0 0 0 0 1 1 0 0 0' logo.bmp
        test -s os-release || cp -pt . root/etc/os-release
elif opt selinux
then test -s vmlinuz.relabel || cp -p /lib/modules/*/vmlinuz vmlinuz.relabel
fi

# Override image generation to drop EROFS support since it's not enabled.
eval "$(
declare -f create_root_image {,un}mount_root | $sed '/[^ ].opt/s/read_only/squash/'
declare -f squash | $sed s/read_only/squash/
declare -f kernel_cmdline | $sed /type=erofs/d
)"

# Override SELinux labeling to work with the CentOS kernel (and no busybox).
function relabel() if opt selinux
then
        local -r root=$(mktemp --directory --tmpdir="$PWD" relabel.XXXXXXXXXX)
        mkdir -p "$root"/{bin,dev,etc,lib,proc,sys,sysroot}
        ln -fns lib "$root/lib64"
        ln -fst "$root/etc" ../sysroot/etc/selinux

        cat << 'EOF' > "$root/init" && chmod 0755 "$root/init"
#!/bin/bash -eux
trap -- 'echo o > /proc/sysrq-trigger ; read -rst 60' EXIT
export PATH=/bin
mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
for mod in sd_mod libata ata_piix jbd2 mbcache ext4
do insmod "/lib/$mod.ko"
done
mount /dev/sda /sysroot
load_policy -i
setfiles -vFr /sysroot{,/etc/selinux/targeted/contexts/files/file_contexts,}
mksquashfs /sysroot /sysroot/squash.img -noappend -comp xz -wildcards -ef /ef
echo SUCCESS > /sysroot/LABEL-SUCCESS
umount /sysroot
EOF

        if opt squash
        then
                disk=squash.img
                echo "$disk" > "$root/ef"
                (IFS=$'\n' ; echo "${exclude_paths[*]}") >> "$root/ef"
                cp -t "$root/bin" /usr/sbin/mksquashfs
        else sed -i -e '/^mksquashfs /d' "$root/init"
        fi

        cp -t "$root/bin" \
            /usr/*bin/{bash,load_policy,mount,setfiles,umount}
        cp /usr/bin/kmod "$root/bin/insmod"
        find /usr/lib/modules/*/kernel '(' \
            -name sd_mod.ko.xz -o \
            -name libata.ko.xz -o -name ata_piix.ko.xz -o \
            -name ext4.ko.xz -o -name jbd2.ko.xz -o -name mbcache.ko.xz -o \
            -false ')' -exec cp -at "$root/lib" '{}' +
        unxz "$root"/lib/*.xz

        { ldd "$root"/bin/* || : ; } |
        sed -n 's,^[^/]\+\(/[^ ]*\).*,\1,p' | sort -u |
        while read -rs ; do cp -t "$root/lib" "$REPLY" ; done

        find "$root" -mindepth 1 -printf '%P\n' |
        cpio -D "$root" -H newc -R 0:0 -o |
        xz --check=crc32 -9e > relabel.img

        umount root
        local -r cores=$(test -e /dev/kvm && nproc)
        /usr/libexec/qemu-kvm -nodefaults -serial stdio < /dev/null \
            ${cores:+-cpu host -smp cores="$cores"} -m 1G \
            -kernel vmlinuz.relabel -append console=ttyS0 \
            -initrd relabel.img /dev/loop-root
        mount /dev/loop-root root
        opt squash && mv -t . "root/$disk"
        test -s root/LABEL-SUCCESS ; rm -f root/LABEL-SUCCESS
fi

# Override squashfs creation since CentOS doesn't support zstd.
eval "$(declare -f squash | $sed 's/ zstd .* 22 / xz /')"

# Override dm-init with userspace since the CentOS kernel is too old.
eval "$(
declare -f kernel_cmdline | $sed 's/opt ramdisk[ &]*dmsetup=/dmsetup=/'
declare -f configure_initrd_generation | $sed 's/if opt ramdisk/if true/'
)"

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFzMWxkBEADHrskpBgN9OphmhRkc7P/YrsAGSvvl7kfu+e9KAaU6f5MeAVyn
rIoM43syyGkgFyWgjZM8/rur7EMPY2yt+2q/1ZfLVCRn9856JqTIq0XRpDUe4nKQ
8BlA7wDVZoSDxUZkSuTIyExbDf0cpw89Tcf62Mxmi8jh74vRlPy1PgjWL5494b3X
5fxDidH4bqPZyxTBqPrUFuo+EfUVEqiGF94Ppq6ZUvrBGOVo1V1+Ifm9CGEK597c
aevcGc1RFlgxIgN84UpuDjPR9/zSndwJ7XsXYvZ6HXcKGagRKsfYDWGPkA5cOL/e
f+yObOnC43yPUvpggQ4KaNJ6+SMTZOKikM8yciyBwLqwrjo8FlJgkv8Vfag/2UR7
JINbyqHHoLUhQ2m6HXSwK4YjtwidF9EUkaBZWrrskYR3IRZLXlWqeOi/+ezYOW0m
vufrkcvsh+TKlVVnuwmEPjJ8mwUSpsLdfPJo1DHsd8FS03SCKPaXFdD7ePfEjiYk
nHpQaKE01aWVSLUiygn7F7rYemGqV9Vt7tBw5pz0vqSC72a5E3zFzIIuHx6aANry
Gat3aqU3qtBXOrA/dPkX9cWE+UR5wo/A2UdKJZLlGhM2WRJ3ltmGT48V9CeS6N9Y
m4CKdzvg7EWjlTlFrd/8WJ2KoqOE9leDPeXRPncubJfJ6LLIHyG09h9kKQARAQAB
tDpDZW50T1MgKENlbnRPUyBPZmZpY2lhbCBTaWduaW5nIEtleSkgPHNlY3VyaXR5
QGNlbnRvcy5vcmc+iQI3BBMBAgAhBQJczFsZAhsDBgsJCAcDAgYVCAIJCgsDFgIB
Ah4BAheAAAoJEAW1VbOEg8ZdjOsP/2ygSxH9jqffOU9SKyJDlraL2gIutqZ3B8pl
Gy/Qnb9QD1EJVb4ZxOEhcY2W9VJfIpnf3yBuAto7zvKe/G1nxH4Bt6WTJQCkUjcs
N3qPWsx1VslsAEz7bXGiHym6Ay4xF28bQ9XYIokIQXd0T2rD3/lNGxNtORZ2bKjD
vOzYzvh2idUIY1DgGWJ11gtHFIA9CvHcW+SMPEhkcKZJAO51ayFBqTSSpiorVwTq
a0cB+cgmCQOI4/MY+kIvzoexfG7xhkUqe0wxmph9RQQxlTbNQDCdaxSgwbF2T+gw
byaDvkS4xtR6Soj7BKjKAmcnf5fn4C5Or0KLUqMzBtDMbfQQihn62iZJN6ZZ/4dg
q4HTqyVpyuzMXsFpJ9L/FqH2DJ4exGGpBv00ba/Zauy7GsqOc5PnNBsYaHCply0X
407DRx51t9YwYI/ttValuehq9+gRJpOTTKp6AjZn/a5Yt3h6jDgpNfM/EyLFIY9z
V6CXqQQ/8JRvaik/JsGCf+eeLZOw4koIjZGEAg04iuyNTjhx0e/QHEVcYAqNLhXG
rCTTbCn3NSUO9qxEXC+K/1m1kaXoCGA0UWlVGZ1JSifbbMx0yxq/brpEZPUYm+32
o8XfbocBWljFUJ+6aljTvZ3LQLKTSPW7TFO+GXycAOmCGhlXh2tlc6iTc41PACqy
yy+mHmSv
=kkH7
-----END PGP PUBLIC KEY BLOCK-----
EOF
        $gpg --verify "$@"
}

# OPTIONAL (BUILDROOT)

function enable_epel() {
        local -r key="RPM-GPG-KEY-EPEL-${options[release]}"
        local -r url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-${options[release]}.noarch.rpm"
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script << EOF
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
curl -L "$url" > epel.rpm
rpm --checksig epel.rpm
rpm --install epel.rpm
exec rm -f epel.rpm
EOF
}

function enable_rpmfusion() {
        local key="RPM-GPG-KEY-rpmfusion-free-el-${options[release]}"
        local url="https://download1.rpmfusion.org/free/el/updates/${options[release]}/$DEFAULT_ARCH/r/rpmfusion-free-release-${options[release]}-0.1.noarch.rpm"
        enable_epel
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script << EOF
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
curl -L "$url" > rpmfusion-nonfree.rpm
curl -L "${url/-release-/-release-tainted-}" > rpmfusion-nonfree-tainted.rpm
rpm --checksig rpmfusion-nonfree{,-tainted}.rpm
rpm --install rpmfusion-nonfree{,-tainted}.rpm
exec rm -f rpmfusion-nonfree{,-tainted}.rpm
EOF
}

# OPTIONAL (IMAGE)

# Override RPMDB saving to drop update reports.  CentOS doesn't give the info.
eval "$(declare -f save_rpm_db | $sed 's/^ *test -x[^|]*/false/')"

# WORKAROUNDS

# The CentOS 7 implementation is so different that it needs its own file.
test "x${options[release]-}" != x7 || . centos7.sh
