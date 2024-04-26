# SPDX-License-Identifier: GPL-3.0-or-later
packages=(aaa_base branding-openSUSE openSUSE-release)
packages_buildroot=()

options[enforcing]=
options[loadpin]=
options[verity_sig]=

function create_buildroot() {
        local -r image="https://download.opensuse.org/tumbleweed/appliances/opensuse-tumbleweed-image.$DEFAULT_ARCH-lxc.tar.xz"

        opt bootable && packages_buildroot+=(kernel-default zstd)
        opt bootable && [[ ${options[arch]:-$DEFAULT_ARCH} == *[3-6x]86* ]] && packages_buildroot+=(ucode-{amd,intel})
        opt gpt && opt uefi && packages_buildroot+=(dosfstools mtools)
        opt read_only && ! opt squash && packages_buildroot+=(erofs-utils)
        opt secureboot && packages_buildroot+=(mozilla-nss-tools pesign)
        opt selinux && packages_buildroot+=(busybox kernel-default policycoreutils qemu-x86 zstd)
        opt squash && packages_buildroot+=(squashfs)
        opt uefi && packages_buildroot+=(binutils distribution-logos-openSUSE-Tumbleweed ImageMagick systemd-boot)
        opt uefi_vars && packages_buildroot+=(ovmf qemu-ovmf-x86_64 qemu-x86)
        opt verity && packages_buildroot+=(cryptsetup device-mapper)
        packages_buildroot+=(curl e2fsprogs glib2-tools openssl)

        $curl -L "$image.sha256" > "$output/checksum"
        $curl -L "$image.sha256.asc" > "$output/checksum.sig"
        $curl -L "$image" > "$output/image.txz"
        verify_distro "$output"/checksum{,.sig} "$output/image.txz"
        $tar -C "$buildroot" -xJf "$output/image.txz"
        $rm -f "$output"/checksum{,.sig} "$output/image.txz"
        $ln -fns ../proc/self/mounts "$buildroot/etc/mtab"

        # Disable non-OSS packages by default.
        $sed -i -e '/^enabled=/s/=.*/=0/' "$buildroot/etc/zypp/repos.d/repo-non-oss.repo"

        # Bypass license checks since it is abused to display random warnings.
        $sed -i -e 's/^[# ]*\(autoAgreeWithLicenses\) *=.*/\1 = yes/' \
            "$buildroot/etc/zypp/zypper.conf"

        # Let the configuration decide if the system should have documentation.
        $sed -i -e 's/^rpm.install.excludedocs/# &/' "$buildroot/etc/zypp/zypp.conf"

        # Disable broken UEFI script.
        ln -fns ../bin/true "$buildroot/usr/sbin/sdbootutil"

        configure_initrd_generation
        initialize_buildroot "$@"

        script "${packages_buildroot[@]}" << 'EOF'
zypper --non-interactive dist-upgrade
zypper --non-interactive update --allow-vendor-change
zypper --non-interactive install --allow-vendor-change "$@"
EOF

        # Don't block important file systems in the initrd.
        $rm -f "$buildroot/usr/lib/modprobe.d/60-blacklist_fs-erofs.conf"
}

function install_packages() {
        opt bootable && packages+=(systemd)
        opt networkd && packages+=(systemd-network)
        opt selinux && packages+=("selinux-policy-${options[selinux]}")

        enable_repo_ports
        zypper --gpg-auto-import-keys --non-interactive --installroot="$PWD/root" \
            install "${packages[@]:-filesystem}" "$@" || [[ $? -eq 107 ]]

        # Define basic users and groups prior to configuring other stuff.
        grep -qs '^wheel:' root/etc/group ||
        groupadd --prefix /wd/root --system --gid=10 wheel

        # Give this distro a compatible firewall before configuring it.
        tee \
            >(test -s root/usr/sbin/iptables-restore && exec sed s/6//g > root/usr/lib/systemd/system/iptables.service || exec cat > /dev/null) \
            << 'EOF' > $(test -s root/usr/sbin/ip6tables-restore && echo root/usr/lib/systemd/system/ip6tables.service || echo /dev/null)
[Unit]
Description=Load ip6tables firewall rules
Before=network-pre.target
Wants=network-pre.target
AssertPathExists=/etc/sysconfig/ip6tables

[Service]
ExecStart=/usr/sbin/ip6tables-restore /etc/sysconfig/ip6tables
ExecReload=/usr/sbin/ip6tables-restore /etc/sysconfig/ip6tables
ExecStop=/usr/sbin/ip6tables -P INPUT ACCEPT
ExecStop=/usr/sbin/ip6tables -P FORWARD ACCEPT
ExecStop=/usr/sbin/ip6tables -P OUTPUT ACCEPT
ExecStop=/usr/sbin/ip6tables -F
ExecStop=/usr/sbin/ip6tables -X
RemainAfterExit=yes
Type=oneshot

[Install]
WantedBy=basic.target
EOF

        # List everything installed in the image and what was used to build it.
        rpm -qa | sort > packages-buildroot.txt
        rpm --root="$PWD/root" -qa | sort > packages.txt
}

function distro_tweaks() {
        rm -fr root/etc/init.d root/usr/lib/modprobe.d/60-blacklist_fs-erofs.conf

        test -s root/usr/share/systemd/tmp.mount &&
        mv -t root/usr/lib/systemd/system root/usr/share/systemd/tmp.mount

        test -s root/etc/zypp/repos.d/repo-non-oss.repo &&
        sed -i -e '/^enabled=/s/=.*/=0/' root/etc/zypp/repos.d/repo-non-oss.repo

        test -s root/usr/share/glib-2.0/schemas/openSUSE-branding.gschema.override &&
        mv root/usr/share/glib-2.0/schemas/{,50_}openSUSE-branding.gschema.override

        test -s root/usr/lib/systemd/system/polkit.service &&
        sed -i -e '/^Type=/iStateDirectory=polkit' root/usr/lib/systemd/system/polkit.service

        test -s root/etc/pam.d/common-auth &&
        sed -i -e 's/try_first_pass/& nullok/' root/etc/pam.d/common-auth

        sed -i -e '1,/ PS1=/s/ PS1="/&$? /' root/etc/bash.bashrc
        echo "alias ll='ls -l'" >> root/etc/skel/.alias
}

function save_boot_files() if opt bootable
then
        opt uefi && test ! -s logo.bmp &&
        sed '/<svg/,/>/s,>,&<style>#g885{display:none}</style>,' /usr/share/pixmaps/distribution-logos/light-dual-branding.svg > /root/logo.svg &&
        magick -background none -size 720x320 /root/logo.svg logo.bmp
        test -s initrd.img || build_systemd_ramdisk "$(cd /lib/modules ; compgen -G "$(rpm -q --qf '%{VERSION}' kernel-default)*")"
        test -s vmlinuz || cp -pt . /lib/modules/*/vmlinuz
fi

# Override relabeling to add the missing modules and fix pthread_cancel.
eval "$(declare -f relabel | $sed \
    -e '/ldd/iopt squash && cp -t "$root/lib" /lib*/libgcc_s.so.1' \
    -e '/find/iln -fns busybox "$root/bin/insmod"\
local mod ; for mod in drivers/ata/ata_piix fs/{jbd2/jbd2,mbcache,ext4/ext4}\
do zstd -cd /lib/modules/*/*/"$mod.ko.zst" > "$root/lib/${mod##*/}.ko"\
sed -i -e "/sda/iinsmod /lib/${mod##*/}.ko" "$root/init" ; done')"

# Override dm-init with userspace since the openSUSE kernel doesn't enable it.
eval "$(declare -f kernel_cmdline | $sed 's/opt ramdisk[ &]*dmsetup=/dmsetup=/')"

# Override default OVMF paths for this distro's packaging.
eval "$(declare -f set_uefi_variables | $sed \
    -e 's,/usr/\S*VARS\S*.fd,/usr/share/qemu/ovmf-x86_64-smm-vars.bin,' \
    -e 's,/usr/\S*CODE\S*.fd,/usr/share/qemu/ovmf-x86_64-smm-code.bin,' \
    -e 's,/usr/\S*/\(Shell\|EnrollDefaultKeys\).efi,/usr/share/ovmf/\1.efi,g')"

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

        # Create a generator to handle verity since dm-init isn't enabled.
        if opt verity
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

function enable_repo_nvidia() {
        local -r repo='https://download.nvidia.com/opensuse/tumbleweed'
        $curl -L "$repo/repodata/repomd.xml.key" > "$output/nvidia.key"
        [[ $($sha256sum "$output/nvidia.key") == 599aa39edfa43fb81e5bf5743396137c93639ce47738f9a2ae8b9a5732c91762\ * ]]
        enter /usr/bin/rpmkeys --import nvidia.key
        $rm -f "$output/nvidia.key"
        echo -e > "$buildroot/etc/zypp/repos.d/nvidia.repo" \
            "[nvidia]\nenabled=1\nautorefresh=1\nbaseurl=$repo\ngpgcheck=1"
}

function enable_repo_ports() if [[ ${options[arch]:-$DEFAULT_ARCH} != $DEFAULT_ARCH ]]
then
        sed -i -e "s/^[# ]*arch *=.*/arch = ${options[arch]}/" /etc/zypp/zypp.conf
        sed -i -e "s,org/,&ports/${options[arch]/#i686/i586}/," /etc/zypp/repos.d/repo-{debug,non-oss,oss,update}.repo
fi

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import
        $gpg --verify "$2" "$1"
        [[ $($sha256sum "$3") == $($sed -n 's/ .*//p' "$1")\ * ]]
} << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGKwfiIBEADe9bKROWax5CI83KUly/ZRDtiCbiSnvWfBK1deAttV+qLTZ006
090eQCOlMtcjhNe641Ahi/SwMsBLNMNich7/ddgNDJ99H8Oen6mBze00Z0Nlg2HZ
VZibSFRYvg+tdivu83a1A1Z5U10Fovwc2awCVWs3i6/XrpXiKZP5/Pi3RV2K7VcG
rt+TUQ3ygiCh1FhKnBfIGS+UMhHwdLUAQ5cB+7eAgba5kSvlWKRymLzgAPVkB/NJ
uqjz+yPZ9LtJZXHYrjq9yaEy0J80Mn9uTmVggZqdTPWx5CnIWv7Y3fnWbkL/uhTR
uDmNfy7a0ULB3qjJXMAnjLE/Oi14UE28XfMtlEmEEeYhtlPlH7hvFDgirRHN6kss
BvOpT+UikqFhJ+IsarAqnnrEbD2nO7Jnt6wnYf9QWPnl93h2e0/qi4JqT9zw93zs
fDENY/yhTuqqvgN6dqaD2ABBNeQENII+VpqjzmnEl8TePPCOb+pELQ7uk6j4D0j7
slQjdns/wUHg8bGE3uMFcZFkokPv6Cw6Aby1ijqBe+qYB9ay7nki44OoOsJvirxv
p00MRgsm+C8he+B8QDZNBWYiPkhHZBFi5GQSUY04FimR2BpudV9rJqbKP0UezEpc
m3tmqLuIc9YCxqMt40tbQOUVSrtFcYlltJ/yTVxu3plUpwtJGQavCJM7RQARAQAB
tDRvcGVuU1VTRSBQcm9qZWN0IFNpZ25pbmcgS2V5IDxvcGVuc3VzZUBvcGVuc3Vz
ZS5vcmc+iQI+BBMBAgAoBQJisH4iAhsDBQkHhM4ABgsJCAcDAgYVCAIJCgsEFgID
AQIeAQIXgAAKCRA1ovhuKbcApKRrEACJMhZhsPJBOkYmANvH5mqlk27brA3IZoM4
8qTzERebzKa0ZH1fgRI/3DhrfBYL0M5XOb3+26Ize0pujyJQs61Nlo1ibtQqCoyu
dvP/pmY1/Vr374wlMFBuCfAjdad4YXkbe7q7GGjo6cF89qtBfTqEtaRrfDgtPLx/
s9/WXLGo0XYqCCSPVoU66jQYNcCt3pH+hqytvntXJDhU+DveOnQCOSBBHhCMST3E
QvriN/GnHf+sO19UmPpyHH0TM5Ru4vDrgzKYKT/CzbllfaJSk9cEuTY8Sv1sP/7B
Z7YvOE0soIgM1sVg0u3R/2ROx0MKoLcq7EtLw64eE+wnw9bHYZQNmS+J/18p7Bo8
I7e+8WRi+m/pus5FEWsIH1uhxKLgJGFDTHHGZtW+myjnUzXVIkpJGrKoolzYjHdK
lRYM2fVuNI1eq6CZ6PFXg2UxovVczSnGMO33HZE09vpgkRDBrw1vF0o/Wnm02kig
V6xYHk5wJx8vL74wPvCbw73UNT9OSdxYAz7JPqGOD6cpKe7XcAH2sYmlGpggAIUz
Rq/lROEF5lx4SxB838JU4ezxD++BJXfBTE8JZmlGscXv74y9nCtSOZza8KOKj8ou
WRl739FMnx9jRd7HHj3TIyymoveODnZ7f3IElyyFsjBW3XuQ9XfpZrIkwHuaZV5M
6q2h+hgWNQ==
=nMh8
-----END PGP PUBLIC KEY BLOCK-----
EOF

# OPTIONAL (IMAGE)

function drop_package() while read -rs
do exclude_paths+=("${REPLY#/}")
done < <(rpm --root="$PWD/root" -qal "$@")
