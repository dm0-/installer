# SPDX-License-Identifier: GPL-3.0-or-later
. fedora.sh  # Inherit Fedora's RPM functions.

options[verity_sig]=

DEFAULT_RELEASE=9

function create_buildroot() {
        local -r cver=20220419.0
        local -r image="https://cloud.centos.org/centos/${options[release]:=$DEFAULT_RELEASE}-stream/$DEFAULT_ARCH/images/CentOS-Stream-Container-Base-${options[release]}-$cver.$DEFAULT_ARCH.tar.xz"

        opt bootable && packages_buildroot+=(kernel-core zstd)
        opt bootable && [[ ${options[arch]:-$DEFAULT_ARCH} == *[3-6x]86* ]] && packages_buildroot+=(microcode_ctl)
        opt bootable && opt squash && packages_buildroot+=(kernel-modules)
        opt gpt && packages_buildroot+=(util-linux)
        opt gpt && opt uefi && packages_buildroot+=(dosfstools glibc-gconv-extra mtools)
        opt secureboot && packages_buildroot+=(pesign)
        opt selinux && packages_buildroot+=(kernel-core policycoreutils qemu-kvm-core zstd)
        opt squash && packages_buildroot+=(squashfs-tools)
        opt uefi && packages_buildroot+=(binutils centos-logos ImageMagick systemd-boot)
        opt verity && packages_buildroot+=(veritysetup)
        opt verity_sig && opt bootable && packages_buildroot+=(kernel-devel keyutils)
        packages_buildroot+=(e2fsprogs openssl util-linux-core)

        $mkdir -p "$buildroot"
        $curl -L "$image" > "$output/image.txz"
        verify_distro "$output/image.txz"
        $tar -C "$output" --transform='s,^\([^/]*/\)\?,tmp/,' -xJf "$output/image.txz"
        $tar -C "$buildroot" -xf "$output/tmp/layer.tar"
        $rm -fr "$output/image.txz" "$output/tmp"

        # Disable bad packaging options.
        $sed -i -e '/^[[]main]/ainstall_weak_deps=False' "$buildroot/etc/dnf/dnf.conf"

        configure_initrd_generation
        initialize_buildroot "$@"

        opt networkd || opt uefi && enable_repo_epel  # EPEL now has core RPMs.
        script "${packages_buildroot[@]}" << 'EOF'
dnf --assumeyes --setopt=tsflags=nodocs upgrade
dnf --assumeyes --setopt=tsflags=nodocs install "$@"
for fw in /lib/firmware/amd-ucode/*.bin.xz ; do unxz "$fw" ; done
EOF
}

function distro_tweaks() {
        exclude_paths+=('usr/lib/.build-id')

        rm -fr root/etc/rc.{d,local}

        mkdir -p root/usr/lib/systemd/system/local-fs.target.wants
        ln -fst root/usr/lib/systemd/system/local-fs.target.wants ../tmp.mount

        test -x root/usr/bin/update-crypto-policies &&
        chroot root /usr/bin/update-crypto-policies --no-reload --set FUTURE

        test -s root/etc/dnf/dnf.conf &&
        sed -i -e '/^[[]main]/ainstall_weak_deps=False' root/etc/dnf/dnf.conf

        test -s root/etc/locale.conf ||
        echo LANG=C.UTF-8 > root/etc/locale.conf

        sed -i -e 's/^[^#]*PS1="./&\\$? /;s/mask 002$/mask 022/' root/etc/bashrc
}

# Override the UEFI logo source to use the dark background variant for CentOS.
eval "$(declare -f save_boot_files | $sed \
    -e 's,fedora\(-logos/fedora_logo\),centos\1_darkbackground,')"

# Override image generation to drop EROFS support since it's not enabled.
eval "$(
declare -f create_root_image {,un}mount_root | $sed \
    -e '/if\|size/s/read_only/squash/' \
    -e 's/! opt ramdisk/{ opt verity || & ; }/'
declare -f squash | $sed '/!/s/read_only/squash/'
declare -f kernel_cmdline | $sed /type=erofs/d
)"

# Override SELinux labeling to work with the CentOS kernel (and no busybox).
function relabel() if opt selinux
then
        local -r root=$(mktemp --directory --tmpdir="$PWD" relabel.XXXXXXXXXX)
        mkdir -p "$root"/{bin,dev,etc,lib,proc,sys,sysroot}
        ln -fns lib "$root/lib64"
        ln -fst "$root/etc" ../sysroot/etc/selinux

        cat << 'EOF' > "$root/init" ; chmod 0755 "$root/init"
#!/bin/bash -eux
trap -- 'echo o > /proc/sysrq-trigger ; read -rst 60' EXIT
export PATH=/bin
mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
for mod in t10-pi sd_mod libata ata_piix jbd2 mbcache ext4
do insmod "/lib/$mod.ko"
done
mount /dev/sda /sysroot
load_policy -i
policy=$(sed -n 's/^SELINUXTYPE=//p' /etc/selinux/config)
/bin/setfiles -vFr /sysroot \
    "/sysroot/etc/selinux/$policy/contexts/files/file_contexts" /sysroot
mksquashfs /sysroot /sysroot/squash.img -noappend -comp zstd -Xcompression-level 22 -wildcards -ef /ef
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
            /usr/*bin/{bash,load_policy,mount,sed,setfiles,umount}
        cp /usr/bin/kmod "$root/bin/insmod"
        find /usr/lib/modules/*/kernel '(' \
            -name t10-pi.ko.xz -o -name sd_mod.ko.xz -o \
            -name libata.ko.xz -o -name ata_piix.ko.xz -o \
            -name ext4.ko.xz -o -name jbd2.ko.xz -o -name mbcache.ko.xz -o \
            -false ')' -exec cp -at "$root/lib" '{}' +
        unxz "$root"/lib/*.xz

        { ldd "$root"/bin/* || : ; } |
        sed -n 's,^[^/]\+\(/[^ ]*\).*,\1,p' | sort -u |
        while read -rs ; do cp -t "$root/lib" "$REPLY" ; done

        find "$root" -mindepth 1 -printf '%P\n' |
        cpio -D "$root" -H newc -R 0:0 -o |
        zstd --threads=0 --ultra -22 > relabel.img

        umount root
        local -r cores=$(test -e /dev/kvm && nproc)
        /usr/libexec/qemu-kvm -nodefaults -no-reboot -serial stdio < /dev/null \
            ${cores:+-cpu host -smp cores="$cores"} -m 1G \
            -kernel /lib/modules/*/vmlinuz -initrd relabel.img \
            -append 'console=ttyS0 enforcing=0 lsm=selinux' \
            -drive file=/dev/loop-root,format=raw,media=disk
        mount /dev/loop-root root
        opt squash && mv -t . "root/$disk"
        test -s root/LABEL-SUCCESS ; rm -f root/LABEL-SUCCESS
fi

# Override early microcode ramdisk creation for CentOS Intel paths.
eval "$(declare -f build_microcode_ramdisk | $sed \
    -e s,lib/firmware/i,usr/share/microcode_ctl/ucode_with_caveats/intel/i,g)"

# Override dm-init with userspace since the CentOS kernel disables it.
eval "$(
declare -f kernel_cmdline | $sed 's/opt ramdisk[ &]*dmsetup=/dmsetup=/'
declare -f configure_initrd_generation | $sed 's/if opt ramdisk/if true/'
)"

# CentOS container releases are horribly broken.  Check sums with no signature.
function verify_distro() [[
        $($sha256sum "$1") == $(case $DEFAULT_ARCH in
            aarch64) echo 8df8b8830bc0dd166dcaa9eb882c000feb1f6c1201b60c88619f0dbf574c092c ;;
            ppc64le) echo 1c8618d48bd98b57fe3ec93b8617756ea6be83230791289bfdeb53b737458b2e ;;
            s390x)   echo 3428f7ae8e7d8e722cade2549a5547d2030c01046efe51dcf90c63354b978753 ;;
            x86_64)  echo 2e46ded9169e612b250489c4c46f883bfe0736edbbc51d550d1800acbe9bc9ac ;;
        esac)\ *
]]

# OPTIONAL (BUILDROOT)

function enable_repo_epel() {
        local -r key="RPM-GPG-KEY-EPEL-${options[release]}"
        local -r url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-${options[release]}.noarch.rpm"
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script "$url"
} << 'EOF'
cat << 'EOG' > /tmp/key ; rpmkeys --import /tmp/key
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGE3mOsBEACsU+XwJWDJVkItBaugXhXIIkb9oe+7aadELuVo0kBmc3HXt/Yp
CJW9hHEiGZ6z2jwgPqyJjZhCvcAWvgzKcvqE+9i0NItV1rzfxrBe2BtUtZmVcuE6
2b+SPfxQ2Hr8llaawRjt8BCFX/ZzM4/1Qk+EzlfTcEcpkMf6wdO7kD6ulBk/tbsW
DHX2lNcxszTf+XP9HXHWJlA2xBfP+Dk4gl4DnO2Y1xR0OSywE/QtvEbN5cY94ieu
n7CBy29AleMhmbnx9pw3NyxcFIAsEZHJoU4ZW9ulAJ/ogttSyAWeacW7eJGW31/Z
39cS+I4KXJgeGRI20RmpqfH0tuT+X5Da59YpjYxkbhSK3HYBVnNPhoJFUc2j5iKy
XLgkapu1xRnEJhw05kr4LCbud0NTvfecqSqa+59kuVc+zWmfTnGTYc0PXZ6Oa3rK
44UOmE6eAT5zd/ToleDO0VesN+EO7CXfRsm7HWGpABF5wNK3vIEF2uRr2VJMvgqS
9eNwhJyOzoca4xFSwCkc6dACGGkV+CqhufdFBhmcAsUotSxe3zmrBjqA0B/nxIvH
DVgOAMnVCe+Lmv8T0mFgqZSJdIUdKjnOLu/GRFhjDKIak4jeMBMTYpVnU+HhMHLq
uDiZkNEvEEGhBQmZuI8J55F/a6UURnxUwT3piyi3Pmr2IFD7ahBxPzOBCQARAQAB
tCdGZWRvcmEgKGVwZWw5KSA8ZXBlbEBmZWRvcmFwcm9qZWN0Lm9yZz6JAk4EEwEI
ADgWIQT/itE0RZcQbs6BO5GKOHK/MihGfAUCYTeY6wIbDwULCQgHAgYVCgkICwIE
FgIDAQIeAQIXgAAKCRCKOHK/MihGfFX/EACBPWv20+ttYu1A5WvtHJPzwbj0U4yF
3zTQpBglQ2UfkRpYdipTlT3Ih6j5h2VmgRPtINCc/ZE28adrWpBoeFIS2YAKOCLC
nZYtHl2nCoLq1U7FSttUGsZ/t8uGCBgnugTfnIYcmlP1jKKA6RJAclK89evDQX5n
R9ZD+Cq3CBMlttvSTCht0qQVlwycedH8iWyYgP/mF0W35BIn7NuuZwWhgR00n/VG
4nbKPOzTWbsP45awcmivdrS74P6mL84WfkghipdmcoyVb1B8ZP4Y/Ke0RXOnLhNe
CfrXXvuW+Pvg2RTfwRDtehGQPAgXbmLmz2ZkV69RGIr54HJv84NDbqZovRTMr7gL
9k3ciCzXCiYQgM8yAyGHV0KEhFSQ1HV7gMnt9UmxbxBE2pGU7vu3CwjYga5DpwU7
w5wu1TmM5KgZtZvuWOTDnqDLf0cKoIbW8FeeCOn24elcj32bnQDuF9DPey1mqcvT
/yEo/Ushyz6CVYxN8DGgcy2M9JOsnmjDx02h6qgWGWDuKgb9jZrvRedpAQCeemEd
fhEs6ihqVxRFl16HxC4EVijybhAL76SsM2nbtIqW1apBQJQpXWtQwwdvgTVpdEtE
r4ArVJYX5LrswnWEQMOelugUG6S3ZjMfcyOa/O0364iY73vyVgaYK+2XtT2usMux
VL469Kj5m13T6w==
=Mjs/
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$1" > epel.rpm
rpm --checksig --define=_pkgverify_{'flags 0x0','level all'} epel.rpm
rpm --install epel.rpm
exec rm -f epel.rpm
EOF

# OPTIONAL (IMAGE)

function save_rpm_db() {
        opt selinux && local policy &&
        for policy in root/etc/selinux/*/contexts/files
        do echo /usr/lib/rpm-db /var/lib/rpm >> "$policy/file_contexts.subs_dist"
        done
        mv root/var/lib/rpm root/usr/lib/rpm-db
        ln -fns ../../usr/lib/rpm-db root/var/lib/rpm
        echo > root/usr/lib/tmpfiles.d/rpm-db.conf \
            'L /var/lib/rpm - - - - ../../usr/lib/rpm-db'
}

# WORKAROUNDS

# Older CentOS releases are still available, but most of them are EOL.
[[ ${options[release]:-$DEFAULT_RELEASE} -ge DEFAULT_RELEASE ]] ||
. "legacy/${options[distro]}$(( --DEFAULT_RELEASE )).sh"
