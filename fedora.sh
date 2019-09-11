packages=(glibc-minimal-langpack)
packages_buildroot=(glibc-minimal-langpack)

DEFAULT_RELEASE=30
options[arch]=
options[release]=$DEFAULT_RELEASE

function create_buildroot() {
        local -a packages=(dnf)

        opt bootable && packages+=(cpio findutils gzip kernel-core)
        opt bootable && opt squash || opt ramdisk && packages+=(kernel-modules)
        opt ramdisk && packages+=(busybox)
        opt selinux && packages+=(policycoreutils)
        opt squash && packages+=(squashfs-tools) || packages+=(e2fsprogs)
        opt verity && packages+=(veritysetup)
        opt uefi && packages+=(binutils fedora-logos ImageMagick)

        $dnf --assumeyes --installroot="$buildroot" \
            --releasever="${options[release]:=$DEFAULT_RELEASE}" \
            --setopt=install_weak_deps=False \
            install "${packages[@]}" "${packages_buildroot[@]}" "$@"

        $sed -i -e '/^\[main]/ainstall_weak_deps=False' "$buildroot/etc/dnf/dnf.conf"
        $sed -i -e 's/^enabled=1.*/enabled=0/' "$buildroot"/etc/yum.repos.d/*modular*.repo
}

function install_packages() {
        opt bootable && packages+=(systemd)
        opt iptables && packages+=(iptables-services)
        opt selinux && packages+=(selinux-policy-targeted)

        dnf --assumeyes --installroot="$PWD/root" \
            ${options[arch]:+--forcearch="${options[arch]}"} \
            --releasever="${options[release]}" \
            install "${packages[@]}" "$@"

        rpm -qa | sort > packages-buildroot.txt
        rpm --root="$PWD/root" -qa | sort > packages.txt
}

function save_boot_files() {
        local -r dropin=/usr/lib/systemd/system/systemd-fsck-root.service.wants
        local -r append=$(mktemp --directory --tmpdir="$PWD" initrd.XXXXXXXXXX)

        mkdir -p "$append$dropin"
        ln -fst "$append$dropin" ../udev-workaround.service
        cat << 'EOF' > "$append${dropin%/*}"/udev-workaround.service
# Work around the initrd not creating /dev/mapper entries.

[Unit]
DefaultDependencies=no
After=systemd-udev-trigger.service
Before=systemd-fsck-root.service

[Service]
ExecStart=/usr/bin/udevadm trigger
RemainAfterExit=yes
Type=oneshot
EOF

        find "$append" -mindepth 1 -printf '%P\n' |
        cpio -D "$append" -R 0:0 -co |
        xz --check=crc32 -9e |
        cat /boot/initramfs-*.img - > initrd.img

        opt uefi && convert -background none /usr/share/fedora-logos/fedora_logo.svg -trim logo.bmp

        cp -pt . /lib/modules/*/vmlinuz
}

function distro_tweaks() {
        exclude_paths+=('usr/lib/.build-id')

        test -x root/usr/bin/update-crypto-policies &&
        chroot root /usr/bin/update-crypto-policies --set FUTURE

        test -s root/etc/dnf/dnf.conf &&
        sed -i -e '/^\[main]/ainstall_weak_deps=False' root/etc/dnf/dnf.conf &&
        sed -i -e 's/^enabled=1.*/enabled=0/' root/etc/yum.repos.d/*modular*.repo

        test -s root/usr/share/glib-2.0/schemas/org.gnome.shell.gschema.xml &&
        cat << 'EOF' > root/usr/share/glib-2.0/schemas/99_fix.brain.damage.gschema.override
[org.gnome.calculator]
angle-units='radians'
button-mode='advanced'
[org.gnome.Charmap.WindowState]
maximized=true
[org.gnome.desktop.a11y]
always-show-universal-access-status=true
[org.gnome.desktop.calendar]
show-weekdate=true
[org.gnome.desktop.input-sources]
xkb-options=['compose:rwin','ctrl:nocaps','grp_led:caps']
[org.gnome.desktop.interface]
clock-format='24h'
clock-show-date=true
clock-show-seconds=true
clock-show-weekday=true
[org.gnome.desktop.media-handling]
automount=false
automount-open=false
autorun-never=true
[org.gnome.desktop.notifications]
show-in-lock-screen=false
[org.gnome.desktop.peripherals.touchpad]
natural-scroll=true
tap-to-click=true
[org.gnome.desktop.privacy]
hide-identity=true
recent-files-max-age=0
remember-app-usage=false
remember-recent-files=false
send-software-usage-stats=false
show-full-name-in-top-bar=false
[org.gnome.desktop.screensaver]
show-full-name-in-top-bar=false
user-switch-enabled=false
[org.gnome.desktop.session]
idle-delay=0
[org.gnome.desktop.wm.keybindings]
panel-main-menu=['<Super>s','<Alt>F1','XF86LaunchA']
panel-run-dialog=['<Super>r','<Alt>F2']
show-desktop=['<Super>d']
[org.gnome.desktop.wm.preferences]
button-layout='menu:minimize,maximize,close'
focus-mode='sloppy'
mouse-button-modifier='<Alt>'
visual-bell=true
[org.gnome.Evince.Default]
continuous=false
sizing-mode='fit-page'
[org.gnome.settings-daemon.peripherals.keyboard]
numlock-state='on'
[org.gnome.settings-daemon.plugins.media-keys]
max-screencast-length=0
on-screen-keyboard='<Super>k'
[org.gnome.settings-daemon.plugins.power]
ambient-enabled=false
idle-dim=false
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
[org.gnome.settings-daemon.plugins.xsettings]
antialiasing='rgba'
hinting='full'
overrides={'Gtk/ButtonImages':<1>,'Gtk/MenuImages':<1>}
[org.gnome.shell]
always-show-log-out=true
favorite-apps=['firefox.desktop','vlc.desktop','gnome-terminal.desktop']
[org.gnome.shell.keybindings]
toggle-application-view=['<Super>a','XF86LaunchB']
[org.gnome.shell.overrides]
focus-change-on-pointer-rest=false
workspaces-only-on-primary=false
[org.gnome.Terminal.Legacy.Keybindings]
full-screen='disabled'
help='disabled'
[org.gnome.Terminal.Legacy.Settings]
default-show-menubar=false
menu-accelerator-enabled=false
[org.gnome.Terminal.Legacy.Profile]
background-color='#000000'
background-transparency-percent=20
foreground-color='#FFFFFF'
login-shell=true
scrollback-lines=100000
scrollback-unlimited=false
scrollbar-policy='never'
use-transparent-background=true
use-theme-colors=false
EOF

        compgen -G 'root/usr/share/glib-2.0/schemas/*.gschema.override' &&
        chroot root /usr/bin/glib-compile-schemas /usr/share/glib-2.0/schemas

        sed -i -e 's/^[^#]*PS1="./&\\$? /;s/mask 002$/mask 022/' root/etc/bashrc
        cat << 'EOF' >> root/etc/skel/.bashrc
function defer() {
        local -r cmd="$(trap -p EXIT)"
        eval "trap -- '$*;'${cmd:8:-5} EXIT"
}
EOF
}

function build_ramdisk() {
        local -r root=$(mktemp --directory --tmpdir="$PWD" ramdisk.XXXXXXXXXX)
        mkdir -p "$root"/{bin,dev,lib,mnt,proc,sys,sysroot}

        cp -a /sbin/busybox "$root/bin/"
        for x in ash insmod losetup mknod mount switch_root
        do ln -fns busybox "$root/bin/$x"
        done

        find /lib/modules/*/kernel '(' \
            -name dm-verity.ko.xz -o \
            -name loop.ko.xz -o \
            -name reed_solomon.ko.xz -o \
            -name squashfs.ko.xz -o \
            -name zstd_decompress.ko.xz -o \
            -false ')' -exec cp -at "$root/lib" '{}' +
        unxz "$root"/lib/*.xz

        cat << 'EOF' > "$root/init" && chmod 0755 "$root/init"
#!/bin/ash -euvx

# Handle boot failures.
abort() { echo "Boot failed with $?; dropping to shell" 1>&2 ; exec ash -i ; }
trap abort EXIT

# Set up kernel interfaces.
mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys

# Create a block device for verity to use.
insmod /lib/loop.ko
mknod -m 0600 /dev/loop0 b 7 0
losetup /dev/loop0 /sysroot/root.img

# Load verity support.  XXX: Not used yet.
insmod /lib/reed_solomon.ko
insmod /lib/dm-verity.ko

# Load support for the root file system.
insmod /lib/zstd_decompress.ko
insmod /lib/squashfs.ko

# Mount the root file system.
mount -o ro /dev/loop0 /sysroot

# Switch to the root file system.
exec switch_root /sysroot /sbin/init
EOF

        ln -fn final.img "$root/sysroot/root.img"
        find "$root" -mindepth 1 -printf '%P\n' |
        cpio -D "$root" -R 0:0 -co |
        xz --check=crc32 -9e > ramdisk.img
}

# OPTIONAL (BUILDROOT)

function enable_rpmfusion() {
        enter /bin/bash -euxo pipefail << EOF
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFrUUycBEADfDoQDUWJBi2QpXmFf7be+DMqBjgSZp3ibe29ON1iLe+gfyFjC
0KCuuz+RdfRizKkovlqMC7ucWqDIkc3fCsoWpb+Hpfw51WvLQCyodB0suHfaY0Rk
k8Jhg5u0qnL8lJfiFEiVesKoUziIf+phLKpITK2LBD0kBNn5OnkWrPwNuN0wyvXP
HAqxz3KZxxwBEn1RwUhYIJCZStaFoTDziWHIB2cYIKSdfquOh1UCVuQj63WnUXNL
e4Wqbc62xJQBZkCfs3+r4FybcGrB07Mju0i7MeWzH6dMHYx6ZkGyA5CmOYfoRV2o
CfOHqm3e+MvHDN+7JF6epNSQyMX47KIA5foJZlMe0RhuO8SwHCMc6d/Zc7iFKmG1
IsWdBzGvJkMv1g4OaEAYRuVO5jWWO4370UVqQ9kvzky3aqGI391wekSSqDbLer6a
8isf4QDEqjzhVswxXg99I4zkXlMcYkBRumGBtq1KkcAtLoobVEg1WbQbQQTu4j/H
ZKgFadwhasJK1jN+PtW+erV0l1KyDzjR4vTRR9AWg9ahsTLtRe9HvkBLBhKtrhW0
oPqOW5I3n0LChnegYy7jit5ZPGS7oZvzbu+zok+lwQFLZdPxM2VuY6DQE8BNdXEP
3nLNGbVubv/MZILOws8/ACiONeW9C+RvzYznwmM+JqqhqmKiyr8WWlBfAQARAQAB
tFNSUE0gRnVzaW9uIGZyZWUgcmVwb3NpdG9yeSBmb3IgRmVkb3JhICgzMCkgPHJw
bWZ1c2lvbi1idWlsZHN5c0BsaXN0cy5ycG1mdXNpb24ub3JnPokCRQQTAQgALxYh
BIDDssbnJ/PgkrRz4D3yzkPArtpuBQJa1FMnAhsDBAsJCAcDFQgKAh4BAheAAAoJ
ED3yzkPArtpusgsP/RmuZOKEgrGL12uWo9OEyZLTjjJ9chJRPDNXPQe7/atNJmWe
WwkWbKcWwSivwGP04SsJF1iWRcSwCOLe5wBSpuM5E1XsDufzKsLH1WkjOtDQ+O8U
kkJwV64WT06FkSUze+cS7ni5LSObVqPvBtbKFl8lWciG1IDlK5++XW2VLD3dghAW
5boFZjoVNZoYhlyeZmtcDVlFdXex5Sw0B/gJY4uaHXBXrA1YyE4vBlrSDYrfh4eU
glSGNMNS++78bQsN/C3VmtXpWsvNJa4jxYaXFOJd5g3iX5ttDQYF46PgJckZVurA
8PT066i4eJOwqDPnOQncsudcpbLPt+0F3cyeDPtjKh+RY48hAhTW0/lDq2onhGPk
SOTDhPrx6vWLqDNBKOio3VloFdEOCsm2OniGZojJADm6m6kErY6n3On3y9TE2GDm
Bx8apPxN7FJvwFqvieZt6B1R+57VStQ0YBCsfC1i5EVsNPnyoNqwvxs2IGsn3P/+
SuCw9+qa5aRsF+jdnHxKMmj1xm8dVtCCLfaMb4cl7wxgq9zolvlbRFnfHfhRoKhp
fs3khghy5i2AU/bOChxRngX2QWR1A117IeADWtuspMFEOyeU5BlMcqjkFdOZI3jX
0VmGnXLcUEIa89z/0ktU6TW3MLQ/laFqj5LhGR9jzaDL6S7pOzNqQT4p3jzJ
=S0gf
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L \
    -O "https://download1.rpmfusion.org/free/fedora/releases/${options[release]}/Everything/x86_64/os/Packages/r/rpmfusion-free-release-${options[release]}-1.noarch.rpm" \
    -O "https://download1.rpmfusion.org/free/fedora/releases/${options[release]}/Everything/x86_64/os/Packages/r/rpmfusion-free-release-tainted-${options[release]}-1.noarch.rpm"
rpm --checksig rpmfusion-free-release-{,tainted-}"${options[release]}"-1.noarch.rpm
rpm --install rpmfusion-free-release-{,tainted-}"${options[release]}"-1.noarch.rpm
exec rm -f rpmfusion-free-release-{,tainted-}"${options[release]}"-1.noarch.rpm
EOF
}

# OPTIONAL (IMAGE)

function save_rpm_db() {
        opt selinux && echo /usr/lib/rpm-db /var/lib/rpm >> root/etc/selinux/targeted/contexts/files/file_contexts.subs
        mv root/var/lib/rpm root/usr/lib/rpm-db
        echo > root/usr/lib/tmpfiles.d/rpm-db.conf \
            'L /var/lib/rpm - - - - ../../usr/lib/rpm-db'
}

function drop_package() while read
do exclude_paths+=("${REPLY#/}")
done < <(rpm --root="$PWD/root" -qal "$@")
