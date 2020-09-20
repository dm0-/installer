packages=()
packages_buildroot=()

options[selinux]=
options[verity_sig]=

function create_buildroot() {
        local -r dir="https://mirrors.kernel.org/archlinux/iso/latest"
        local -r release=$($curl -L "$dir/md5sums.txt" | $sed -n 's/.*-bootstrap-\([0-9.]*\)-.*/\1/p')
        local -r image="$dir/archlinux-bootstrap-$release-$DEFAULT_ARCH.tar.gz"

        opt bootable && packages_buildroot+=(dracut intel-ucode linux-firmware linux-hardened)
        opt gpt && opt uefi && packages_buildroot+=(dosfstools mtools)
        opt secureboot && packages_buildroot+=(pesign)
        opt squash && packages_buildroot+=(squashfs-tools)
        opt uefi && packages_buildroot+=(binutils librsvg imagemagick)

        $mkdir -p "$buildroot"
        $curl -L "$image" > "$output/image.tgz"
        $curl -L "$image.sig" | verify_distro - "$output/image.tgz"
        $tar --strip-components=1 -C "$buildroot" -xzf "$output/image.tgz"
        $rm -f "$output/image.tgz"

        # Use the kernel.org and rackspace.com mirrors.
        $sed -i \
            -e '1,/https.*rackspace/{/https.*rackspace/s/^#*//;}' \
            -e '/https.*kernel.org/s/^#*//' \
            "$buildroot/etc/pacman.d/mirrorlist"

        # Fetch EROFS utilities from AUR since they're not in community yet.
        if opt read_only && ! opt squash
        then
                $curl -L 'https://aur.archlinux.org/cgit/aur.git/snapshot/aur-3ffbe2a97e7f6f459b8d34391d65422979debda0.tar.gz' > "$output/erofs-utils.tgz"
                test x$($sha256sum "$output/erofs-utils.tgz" | $sed -n '1s/ .*//p') = xe85e2c7e7d0e7b8e9c8987af7ce7d6844a9a9048e53f1c48d3a3b30b157079b6
                $tar --transform='s,^/*[^/]*,erofs-utils,' -C "$output" -xvf "$output/erofs-utils.tgz" ; $rm -f "$output/erofs-utils.tgz"
                $sed -i -e 's/1\.0/1.1/g;s/508e[0-9a-f]*/a14a30d0d941f6642cad130fbba70a2493fabbe7baa09a8ce7d20745ea3385d6/' "$output"/erofs-utils/{.SRCINFO,PKGBUILD}
                packages_buildroot+=(base-devel)
        fi

        configure_initrd_generation
        initialize_buildroot

        script "${packages_buildroot[@]}" "$@" << 'EOF'
pacman-key --init
pacman-key --populate archlinux
pacman --noconfirm --sync --needed --refresh{,} --sysupgrade{,} "$@"

# Work around Arch not providing Intel microcode so dracut can find it.
test -e /boot/intel-ucode.img && mkdir -p /lib/firmware/intel-ucode &&
cpio --to-stdout -i < /boot/intel-ucode.img > /lib/firmware/intel-ucode/all.img

# Build and install an erofs-utils package from source.
if test -d erofs-utils
then
        mv erofs-utils /home/build ; useradd build ; chown -R build /home/build
        su -c 'exec makepkg PKGBUILD' - build
        pacman --noconfirm --upgrade /home/build/erofs-utils-*.pkg.tar.xz
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
        echo 'LANG="en_US.UTF-8"' > root/etc/locale.conf

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
        sed '/<svg/,/>/s,>,&<style>text{display:none}</style>,' /usr/share/pixmaps/archlinux.svg > /root/logo.svg &&
        magick -background none /root/logo.svg -color-matrix '0 1 0 0 0 0 0 1 0 0 0 0 0 0 1 0 0 0 1 0 1 0 0 0 0' logo.bmp
        test -s initrd.img || build_systemd_ramdisk "$(cd /lib/modules ; compgen -G '[0-9]*')"
        test -s vmlinuz || cp -pt . /lib/modules/*/vmlinuz
fi

# Override dm-init with userspace since the Arch kernel doesn't enable it.
eval "$(declare -f kernel_cmdline | $sed 's/opt ramdisk[ &]*dmsetup=/dmsetup=/')"

function configure_initrd_generation() if opt bootable
then
        # Don't expect that the build system is the target system.
        $mkdir -p "$buildroot/etc/dracut.conf.d"
        echo 'hostonly="no"' > "$buildroot/etc/dracut.conf.d/99-settings.conf"

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

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQENBE2heeUBCADDi8aOa7BFXWVCO/Ygol5pHptu1I9Cndg7OLj4enLeSoRFBgc2
pOrIu8beFMeEVRWq8DsIgS6s2tSp+booatUyw6wMTLp59SNJsuHwJM5JfLtOlvP2
0hTBpy72HaBo16t2xfqZnboq9Zb4kGKhvGnakQXsbJLnth6Ln0Z3ykJtO9JrOb0a
pu86N+EHKrYH/ir/grcn5or6yJUTYDNvvFVWmP99yNhXp8Y1c8FozmQo0wEhWq+O
AM010hDVmU1WjpsSJR5XQuKEgxJoxKl5bltcnzJnB1tquFRLFggWOzWi4Hf20V4w
d7uMG8S7hgK70CHtznOAsDcL3LcvTeSIvGF3ABEBAAG0JFBpZXJyZSBTY2htaXR6
IDxwaWVycmVAYXJjaGxpbnV4LmRlPokBOAQTAQIAIgUCTaF55QIbAwYLCQgHAwIG
FQgCCQoLBBYCAwECHgECF4AACgkQfy1DS5dB6Kz5CAf8D9ZEML504eAt6OVJcWPu
shkc4fFm5fCMXz76cpgxkUr/4ca0RZYtjNw1JpT4jor7YtpaDEhhxc6jXqKe7E0l
VYPuuLJAj4ND1zhPYizfsNgM6e8P+VfPi/fFMTyIPv+14Wzc3ymleUqq4rWoUHgO
Kfv8UcAA1S3UeBnMXV0dBNNii41IE6mx++EiLiqeChDxX+sGRtUYblRmdapfi/gl
X/sSAujbmwnqDgIO/lKSxWXklyXIjjxPXSoFn/Ee0Nc+klv3MSjiFYoCoqNDR6rI
KGcc49OikBagWb2SIt/9UWSZOI7YCsR9pGRKf7bxCWMqUA3SVwiyMFmONvvLxo/z
ubkBDQRNoXnlAQgAw8Twos3KzoR9dkWyJPHp0rK2wE20J0oKVNwxxe+o9oFSLbAc
6X42IEAng+SmrF7hZhRaYdqWO96grqA0MRU6OICTWbfdP6Fewv7zxMDGOTJB3Stm
wdwZWc57IZKRzZlkQSrwqxydPY2cZgiAnjcpoTMgGARljOzEwsxLCpPQrqZcReUA
KQm1sLZWVaYMa2vdDMwVZUE/hK14i5V7fERuu90ZRnhaTncViuFEm69QL6mMTFem
OLP5iqXACUAXS+SHkU/AZ2huZlY0tFIDfDHjenPjZb35xQWRfVxWV3xSdUKw2p3s
k9fNYLigeGqcZr7cl8Q/TmHVvxFxmxqXWxdzsQARAQABiQEfBBgBAgAJBQJNoXnl
AhsMAAoJEH8tQ0uXQeisvOYH/R7TzLJySKosyXebNqEZKWMT4siyqavtJR9kfsj6
NUMre86UdUlfIklQ2k4msXxeAcGUM9ELdBZyKa81riMNhYxJRP7VRR/hcPUlubd9
Zcvr/412vohnDFyG5Q1+SNIKn311SURs2cz0A1dGL+M8j/9h7L9BdudDdjfP3Gaj
2l+SdHSqzoQ5oucnOVqGCc82Vc10bl8Mwp3J9MpmbXjhsHGluJJmk0D2994nZkxP
PaV57JIEBaX7QHbz8PUH/841YU7RV/ecLaDT3GDrTCAEafzno2swR2kVvjSFsgr4
+/DEaMvbNEzgM8HMjglqY8x7j77JYP1NBxK2wxoTbGvP3Zw=
=I12s
-----END PGP PUBLIC KEY BLOCK-----
EOF
        $gpg --verify "$@"
}
