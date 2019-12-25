DEFAULT_ARCH=$($uname -m)
disk=ext4.img
exclude_paths=({boot,dev,home,media,proc,run,srv,sys,tmp}/'*')

declare -A options
options[distro]=fedora
options[bootable]=    # Include a kernel and init system to boot the image
options[executable]=  # Create an executable disk image file
options[networkd]=    # Enable minimal DHCP networking without NetworkManager
options[nvme]=        # Support root on an NVMe disk.
options[partuuid]=    # The partition UUID for verity to map into the root FS
options[ramdisk]=     # Produce an initrd that sets up the root FS in memory
options[read_only]=   # Use tmpfs in places to make a read-only system usable
options[selinux]=     # Enforce SELinux policy
options[squash]=      # Produce a compressed squashfs image
options[uefi]=        # Generate a single UEFI executable containing boot files
options[verity]=      # Prevent file system modification with dm-verity

function usage() {
        echo "Usage: $0 [-BKRSUVZhu] \
[-E <uefi-binary-path>] [[-I] -P <partuuid>] \
[-c <pem-certificate> -k <pem-private-key>] \
[-a <userspec>] [-d <distro>] [-p <package-list>] \
[<config.sh> [<parameter>]...]

This program will produce a root file system from a given system configuration
file.  Parameters after the configuration file are passed to it, so their
meanings are specific to each system (typically listing paths for host files to
be copied into the build root).

The output options described below can change or ammend the produced files, but
the configuration file can forcibly enable them to declare they are a required
part of the system, or disable them to declare they are incompatible with it.

Output format options:
  -B    Include a kernel and init program to produce a bootable system.
  -K    Bundle the root file system in the initrd to run in RAM (implying -B).
  -R    Make the system run in read-only mode with tmpfs mounts where needed.
  -S    Use squashfs as the root file system for compression (implying -R).
  -U    Generate a UEFI executable that boots into the system (implying -B).
  -V    Attach verity signatures to the root file system image (implying -R).
  -Z    Install and enforce targeted SELinux policy, and label the file system.

Install options:
  -E <uefi-binary-path>
        Save the UEFI executable to the given path, which should be on the
        mounted target ESP file system (implying -U).
        Example: -E /boot/EFI/BOOT/BOOTX64.EFI
  -I    Install the file system to disk on the partition specified with -P.
  -P <partuuid>
        Configure the kernel arguments to use the given GPT partition UUID as
        the root file system on boot.  If this option is not used, the kernel
        will assume that the root file system is on /dev/sda.
        Example: -P e08ede5f-56d4-4d6d-b8d9-abf7ef5be608

Signing options:
  -c <pem-certificate>
        Use the given PEM certificate for Secure Boot signing.  When not using
        UEFI, the certificate can still be used e.g. for kernel module signing.
  -k <pem-private-key>
        Use the given PEM private key for Secure Boot signing.  When not using
        UEFI, the private key can still be used e.g. for kernel module signing.

Customization options:
  -a <username>:[<uid>]:[<group-list>]:[<comment>]
        Add a passwordless user to the image.  If the UID is omitted, the next
        available number will be used.  The group list contains comma-separated
        names of supplementary groups for the user in addition to its primary
        group.  The comment (GECOS) field is usually used for a readable name.
        This option can be used multiple times to create more accounts.
        Example: -a 'user::wheel:Sysadmin Account'
  -d <distro>
        Select the distro to install (default: fedora).  This is only used when
        a system definition file does not specify the distro.
        Example: -d centos
  -p <package-list>
        Install the given space-separated list of packages into the image in
        addition to the package set in the system definition file.
        Example: -p 'man-db sudo wget'

Help options:
  -h    Output this help text.
  -u    Output a single line of brief usage syntax."
}

function imply_options() {
        opt squash || opt verity && options[read_only]=1
        opt uefi_path && options[uefi]=1
        opt uefi || opt ramdisk && options[bootable]=1
        opt executable && opt uefi && ! opt ramdisk && ! opt partuuid &&
        options[partuuid]=$(</proc/sys/kernel/random/uuid)
        opt distro || options[distro]=fedora  # This can't be unset.
}

function validate_options() {
        # Secure Boot signing requires both a key and a certificate.
        opt sb_cert && opt sb_key ; opt sb_cert && test -s "${options[sb_cert]}"
        opt sb_key && opt sb_cert ; opt sb_key && test -s "${options[sb_key]}"
        # Validate form, but don't look for a device yet (because hot-plugging exists).
        opt partuuid &&
        [[ ${options[partuuid]} =~ ^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$ ]]
        # A partition UUID must be set to create a bootable UEFI disk image.
        opt executable && opt uefi && ! opt ramdisk && opt partuuid
        # A partition is required when writing to disk.
        opt install_to_disk && opt partuuid
        # A UEFI executable is required in order to save it.
        opt uefi_path && opt uefi
        # Enforce the read-only setting when writing is unsupported.
        opt squash || opt verity && opt read_only
        # The distro must be set or something went wrong.
        opt distro
}

function opt() { test -n "${options["${*?}"]-}" ; }

function enter() {
        $nspawn \
            --bind="$output:/wd" \
            $(test -e /dev/kvm && echo --bind=/dev/kvm) \
            ${loop:+--bind="$loop:/dev/loop-root"} \
            --chdir=/wd \
            --directory="$buildroot" \
            --machine="buildroot-${output##*.}" \
            --quiet \
            "$@"
}

function script() {
        $cat <([[ $- =~ x ]] && echo "PS4='+\e[34m+\e[0m '"$'\nset -x') - |
        enter /bin/bash -euo pipefail -O nullglob -- /dev/stdin "$@"
}

function script_with_keydb() if opt sb_cert && opt sb_key
then enter /bin/bash -euo pipefail -O nullglob -- /dev/stdin "$@" << EOF
PS4='+\e[34m+\e[0m '
$([[ $- =~ x ]] && echo 'set -x')
keydir=\$(mktemp -d)
cat << 'EOP-' > "\$keydir/sign.key"
$(<"${options[sb_key]}")
EOP-
cat << 'EOP-' > "\$keydir/sign.crt"
$(<"${options[sb_cert]}")
EOP-
cat "\$keydir/sign.crt" <(echo) "\$keydir/sign.key" > "\$keydir/sign.pem"
if ${options[uefi]:+:} false
then
        openssl pkcs12 -export \
            -in "\$keydir/sign.crt" -inkey "\$keydir/sign.key" \
            -name sb -out "\$keydir/sign.p12" -password pass:
        certutil --empty-password -N -d "\$keydir"
        pk12util -W '' -d "\$keydir" -i "\$keydir/sign.p12"
fi
{
$(</dev/stdin)
} < /dev/null
EOF
else script "$@"
fi

# Distros should override these functions.
function create_buildroot() { : ; }
function install_packages() { : ; }
function distro_tweaks() { : ; }
function save_boot_files() { : ; }

# Systems should override these functions.
function initialize_buildroot() { : ; }
function customize_buildroot() { : ; }
function customize() { : ; }

function create_root_image() if opt selinux || ! opt read_only
then
        local -r size=$(opt read_only && echo 10 || echo 4)G
        $truncate --size="${1:-$size}" "$output/$disk"
        declare -g loop=$($losetup --show --find "$output/$disk")
        trap -- '$losetup --detach "$loop"' EXIT
fi

function mount_root() if opt selinux || ! opt read_only
then
        mkfs.ext4 -m 0 /dev/loop-root
        mount -o X-mount.mkdir /dev/loop-root root
fi

function unmount_root() if opt selinux || ! opt read_only
then
        e4defrag root
        umount root
        opt read_only && tune2fs -O read-only /dev/loop-root
        e2fsck -Dfy /dev/loop-root || [ "$?" -eq 1 ]
fi

function relabel() if opt selinux
then
        local -r root=$(mktemp --directory --tmpdir="$PWD" relabel.XXXXXXXXXX)
        mkdir -p "$root"/{bin,dev,etc,lib,proc,sys,sysroot}
        ln -fns lib "$root/lib64"
        ln -fst "$root/etc" ../sysroot/etc/selinux

        cat << 'EOF' > "$root/init" && chmod 0755 "$root/init"
#!/bin/ash -eux
trap -- 'poweroff -f ; exec sleep 60' EXIT
export PATH=/bin
mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount /dev/sda /sysroot
/bin/load_policy -i
/bin/setfiles -vFr /sysroot \
    /sysroot/etc/selinux/targeted/contexts/files/file_contexts /sysroot
test -x /bin/mksquashfs && /bin/mksquashfs /sysroot /sysroot/squash.img \
    -noappend -comp zstd -Xcompression-level 22 -wildcards -ef /ef
test -x /bin/mkfs.erofs && /bin/mkfs.erofs -Eforce-inode-compact \
    /sysroot/erofs.img /sysroot
echo SUCCESS > /sysroot/LABEL-SUCCESS
umount /sysroot
EOF

        if opt squash
        then
                disk=squash.img
                echo "$disk" > "$root/ef"
                (IFS=$'\n' ; echo "${exclude_paths[*]}") >> "$root/ef"
                cp -t "$root/bin" /usr/*bin/mksquashfs
        elif opt read_only
        then
                disk=erofs.img
                cp -t "$root/bin" /usr/*bin/mkfs.erofs
        fi

        local cmd
        cp -t "$root/bin" /*bin/busybox /usr/sbin/{load_policy,setfiles}
        for cmd in ash echo mount poweroff sleep umount
        do ln -fns busybox "$root/bin/$cmd"
        done

        { ldd "$root"/bin/* || : ; } |
        sed -n 's,^[^/]\+\(/[^ ]*\).*,\1,p' | sort -u |
        while read -rs ; do cp -t "$root/lib" "$REPLY" ; done

        find "$root" -mindepth 1 -printf '%P\n' |
        cpio -D "$root" -H newc -R 0:0 -o |
        xz --check=crc32 -9e > relabel.img

        umount root
        local -r cores=$(test -e /dev/kvm && nproc)
        qemu-system-x86_64 -nodefaults -serial stdio < /dev/null \
            ${cores:+-enable-kvm -cpu host -smp cores="$cores"} -m 1G \
            -kernel vmlinuz.relabel -append console=ttyS0 \
            -initrd relabel.img /dev/loop-root
        mount /dev/loop-root root
        opt read_only && mv -t . "root/$disk"
        test -s root/LABEL-SUCCESS ; rm -f root/LABEL-SUCCESS
fi

function squash() if opt squash && ! opt selinux
then
        local -r IFS=$'\n'
        disk=squash.img
        mksquashfs root "$disk" -noappend -no-xattrs \
            -comp zstd -Xcompression-level 22 \
            -wildcards -ef /dev/stdin <<< "${exclude_paths[*]}"
elif opt read_only && ! opt selinux
then
        local path
        for path in "${exclude_paths[@]}"
        do compgen -G "root/$path" || :
        done | xargs --delimiter='\n' -- rm -fr
        disk=erofs.img
        mkfs.erofs -Eforce-inode-compact -x-1 "$disk" root
fi

function verity() if opt verity
then
        local -ir size=$(stat --format=%s "$disk")
        local -A verity
        local root=/dev/sda
        ! (( size % 4096 ))

        opt partuuid && root=PARTUUID=${options[partuuid]}
        opt ramdisk && root=/dev/loop0

        while read -rs
        do verity[${REPLY%%:*}]=${REPLY#*:}
        done < <(veritysetup format "$disk" signatures.img)

        echo > dmsetup.txt \
            root,,,ro,0 $(( size / 512 )) \
            verity ${verity[Hash type]} $root $root \
            ${verity[Data block size]} ${verity[Hash block size]} \
            ${verity[Data blocks]} $(( ${verity[Data blocks]} + 1 )) \
            ${verity[Hash algorithm]} ${verity[Root hash]} \
            ${verity[Salt]} 0

        cat "$disk" signatures.img > final.img
else ln -fn "$disk" final.img
fi

function build_ramdisk() if opt ramdisk
then
        local -r root=$(mktemp --directory --tmpdir="$PWD" ramdisk.XXXXXXXXXX)
        mkdir -p "$root/usr/lib/systemd/system/dev-loop0.device.requires"
        cat << EOF > "$root/usr/lib/systemd/system/losetup-root.service"
[Unit]
DefaultDependencies=no
After=systemd-tmpfiles-setup-dev.service
Requires=systemd-tmpfiles-setup-dev.service
[Service]
ExecStart=/usr/sbin/losetup --find $(opt read_only && echo --read-only) /sysroot/root.img
RemainAfterExit=yes
Type=oneshot
EOF
        ln -fst "$root/usr/lib/systemd/system/dev-loop0.device.requires" ../losetup-root.service
        mkdir -p "$root/sysroot"
        ln -fn final.img "$root/sysroot/root.img"
        find "$root" -mindepth 1 -printf '%P\n' |
        cpio -D "$root" -H newc -R 0:0 -o |
        xz --check=crc32 -9e | cat initrd.img - > ramdisk.img
fi

function kernel_cmdline() if opt bootable
then
        local dmsetup=dm-mod.create
        local root=/dev/sda
        local type=ext4

        opt ramdisk && dmsetup=DVR

        opt partuuid && root=PARTUUID=${options[partuuid]}
        opt ramdisk && root=/dev/loop0
        opt verity && root=/dev/dm-0

        opt read_only && type=erofs
        opt squash && type=squashfs

        echo > kernel_args.txt \
            $(opt read_only && echo ro || echo rw) \
            "root=$root" \
            "rootfstype=$type" \
            $(opt verity && echo "$dmsetup=\"$(<dmsetup.txt)\"")
fi

function tmpfs_var() if opt read_only
then
        exclude_paths+=(var/'*')

        mkdir -p root/usr/lib/systemd/system
        cat << EOF > root/usr/lib/systemd/system/var.mount
[Unit]
Description=Mount writable tmpfs over /var
ConditionPathIsMountPoint=!/var

[Mount]
What=tmpfs
Where=/var
Type=tmpfs
Options=${options[selinux]:+rootcontext=system_u:object_r:var_t:s0,}mode=0755,strictatime,nodev,nosuid

[Install]
WantedBy=local-fs.target
EOF
fi

function tmpfs_home() if opt read_only
then
        cat << EOF > root/usr/lib/systemd/system/home.mount
[Unit]
Description=Mount tmpfs over /home to create new users
ConditionPathIsMountPoint=!/home
ConditionPathIsSymbolicLink=!/home

[Mount]
What=tmpfs
Where=/home
Type=tmpfs
Options=${options[selinux]:+rootcontext=system_u:object_r:home_root_t:s0,}mode=0755,strictatime,nodev,nosuid

[Install]
WantedBy=local-fs.target
EOF

        cat << EOF > root/usr/lib/systemd/system/root.mount
[Unit]
Description=Mount tmpfs over /root
ConditionPathIsMountPoint=!/root
ConditionPathIsSymbolicLink=!/root

[Mount]
What=tmpfs
Where=/root
Type=tmpfs
Options=${options[selinux]:+rootcontext=system_u:object_r:admin_home_t:s0,}mode=0700,strictatime,nodev,nosuid

[Install]
WantedBy=local-fs.target
EOF

        mkdir -p root/usr/lib/systemd/system/local-fs.target.wants
        ln -fst root/usr/lib/systemd/system/local-fs.target.wants \
            ../home.mount ../root.mount

        test -s root/etc/pam.d/system-auth &&
        echo >> root/etc/pam.d/system-auth \
            'session     required      pam_mkhomedir.so'

        cat << 'EOF' > root/usr/lib/tmpfiles.d/root.conf
C /root - - - - /etc/skel
Z /root
EOF
fi

function overlay_etc() if opt read_only
then
        cat << 'EOF' > root/usr/lib/systemd/system/etc-overlay-setup.service
[Unit]
Description=Set up overlay working directories for /etc in /run
DefaultDependencies=no
RequiresMountsFor=/run

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/mkdir -Zpm 0755 /run/etcgo/overlay /run/etcgo/wd
EOF

        cat << 'EOF' > root/usr/lib/systemd/system/etc.mount
[Unit]
Description=Mount a writable overlay over /etc
ConditionPathIsMountPoint=!/etc
After=etc-overlay-setup.service
Requires=etc-overlay-setup.service

[Mount]
What=overlay
Where=/etc
Type=overlay
Options=strictatime,nodev,nosuid,lowerdir=/etc,upperdir=/run/etcgo/overlay,workdir=/run/etcgo/wd

[Install]
RequiredBy=local-fs.target
EOF
        mkdir -p root/usr/lib/systemd/system/local-fs.target.wants
        ln -fst root/usr/lib/systemd/system/local-fs.target.wants ../etc.mount

        opt selinux && echo /run/etcgo/overlay /etc >> root/etc/selinux/targeted/contexts/files/file_contexts.subs

        if test -x root/usr/bin/git
        then
                cat << 'EOF' > root/usr/lib/systemd/system/etcgo.service
[Unit]
Description=Restore the /etc overlay from Git
DefaultDependencies=no
RefuseManualStop=yes

[Service]
ExecStartPre=/bin/bash -c "if ! compgen -G '*' > /dev/null ; then \
/usr/bin/git init --bare ; \
echo 'System configuration overlay tracker' > description ; \
echo -e '[user]\n\tname = root\n\temail = root@localhost' >> config ; \
/usr/bin/git --work-tree=/ commit --allow-empty --message='Repository created' ; \
fi"
ExecStart=/usr/bin/git worktree add --force -B master ../../../run/etcgo/overlay master
ExecStartPost=-/usr/sbin/restorecon -vFR /run/etcgo/overlay
RemainAfterExit=yes
RuntimeDirectory=etcgo etcgo/overlay etcgo/wd
RuntimeDirectoryPreserve=yes
StateDirectory=etcgo
StateDirectoryMode=0700
Type=oneshot
WorkingDirectory=/var/lib/etcgo
EOF
                rm -f root/usr/lib/systemd/system/etc-overlay-setup.service
                sed -i -e s/-overlay-setup/go/ root/usr/lib/systemd/system/etc.mount
        fi
fi

eval "function configure_packages() {
$($cat configure.pkg.d/[!.]*.sh 0<&-)
}"

function configure_system() {
        sed -i -e 's/^root:[^:]*/root:*/' root/etc/shadow
        opt adduser && (IFS=$'\n'
                for spec in ${options[adduser]}
                do
                        spec+=::::
                        name=${spec%%:*}
                        uid=${spec#*:} uid=${uid%%:*}
                        groups=${spec#*:*:} groups=${groups%%:*}
                        gecos=${spec#*:*:*:} gecos=${gecos%%:*}
                        useradd --prefix root \
                            ${gecos:+--comment="$gecos"} \
                            ${groups:+--groups="$groups"} \
                            ${uid:+--uid="$uid"} \
                            --password= "$name"
                done
        )

        test -s root/etc/sudoers &&
        sed -i -e '/%wheel/{s/^[# ]*/# /;/NOPASSWD/s/^[# ]*//;}' root/etc/sudoers

        test -s root/etc/profile &&
        sed -i -e 's/ umask 0[0-7]*/ umask 022/' root/etc/profile

        cat << 'EOF' >> root/etc/skel/.bashrc
function defer() {
        local -r cmd="$(trap -p EXIT)"
        eval "trap -- '$*;'${cmd:8:-5} EXIT"
}
EOF

        test -d root/usr/lib/locale/en_US.utf8 &&
        echo 'LANG="en_US.UTF-8"' > root/etc/locale.conf

        ln -fns ../usr/share/zoneinfo/America/New_York root/etc/localtime

        # WORKAROUNDS

        cat << 'EOF' > root/usr/lib/tmpfiles.d/var-mail.conf
# User modification commands expect a mail spool directory to exist.
d /var/mail 0775 root mail
L /var/spool/mail - - - - ../mail
EOF

        mkdir -p root/usr/lib/systemd/system/systemd-random-seed.service.d
        cat << 'EOF' > root/usr/lib/systemd/system/systemd-random-seed.service.d/mkdir.conf
# SELinux prevents the service from creating the directory before tmpfiles.
[Service]
ExecStartPre=-/usr/bin/mkdir -p /var/lib/systemd
ExecStartPre=-/usr/sbin/restorecon -vFR /var
EOF
}

function finalize_packages() {
        local dir

        # Regenerate gsettings defaults.
        test -d root/usr/share/glib-2.0/schemas &&
        glib-compile-schemas root/usr/share/glib-2.0/schemas

        # Run depmod when kernel modules are installed.
        dir=$(compgen -G 'root/lib/modules/*') &&
        depmod --basedir=root "${dir##*/}"

        # Move the giant hardware database to /usr when udev is installed.
        rm -f root/etc/udev/hwdb.bin
        test -x /bin/systemd-hwdb && systemd-hwdb --root=root --usr update

        # Create users now so it doesn't need to happen during boot.
        systemd-sysusers --root=root
}

function produce_uefi_exe() if opt uefi
then
        local -r kargs=$(test -s kernel_args.txt && echo kernel_args.txt)
        local -r logo=$(test -s logo.bmp && echo logo.bmp)
        local -r osrelease=$(test -s os-release && echo os-release)
        local initrd=$(opt ramdisk && echo ramdisk || echo initrd).img
        test -s "$initrd" || initrd=

        objcopy \
            ${osrelease:+--add-section .osrel="$osrelease" --change-section-vma .osrel=0x20000} \
            ${kargs:+--add-section .cmdline="$kargs" --change-section-vma .cmdline=0x30000} \
            ${logo:+--add-section .splash="$logo" --change-section-vma .splash=0x40000} \
            --add-section .linux=vmlinuz --change-section-vma .linux=0x2000000 \
            ${initrd:+--add-section .initrd="$initrd" --change-section-vma .initrd=0x3000000} \
            /usr/lib/systemd/boot/efi/linuxx64.efi.stub unsigned.efi

        if opt sb_cert && opt sb_key
        then
                pesign --certdir="$keydir" --certificate=sb --force \
                    --in=unsigned.efi --out=BOOTX64.EFI --sign
        else ln -fn unsigned.efi BOOTX64.EFI
        fi
fi

function produce_executable_image() if opt executable
then
        local -ir bs=512 start=2048
        local -i esp=0 size=0

        # The disk image has a root file system when not using a UEFI ramdisk.
        opt ramdisk && opt uefi || size=$(stat --format=%s final.img)
        (( size % bs )) && size+=$(( bs - size % bs ))

        # The disk image has an ESP when using a UEFI binary.
        opt uefi && esp=$(( $(stat --format=%s BOOTX64.EFI) + 5242880 ))
        esp=$(( (esp - esp % 1048576) / bs ))

        # Format a disk image with the appropriate partition layout.
        truncate --size=$(( size + (start + esp + 33) * bs )) disk.exe
        if opt ramdisk && opt uefi
        then
                echo g \
                    n 1 $start $(( start + esp - 1 )) \
                    t c12a7328-f81f-11d2-ba4b-00a0c93ec93b \
                    w
        elif opt uefi
        then
                echo g \
                    n 1 $start $(( start + esp - 1 )) \
                    n 2 $(( start + esp )) $(( size / bs + start + esp - 1 )) \
                    t 1 c12a7328-f81f-11d2-ba4b-00a0c93ec93b \
                    t 2 0fc63daf-8483-4772-8e79-3d69d8477de4 \
                    ${options[partuuid]:+x u 2 "${options[partuuid]}" r} \
                    w
        else
                echo g \
                    n 1 $start $(( size / bs + start - 1 )) \
                    t 0fc63daf-8483-4772-8e79-3d69d8477de4 \
                    ${options[partuuid]:+x u "${options[partuuid]}" r} \
                    w
        fi | tr ' ' '\n' | fdisk disk.exe

        # Create the ESP without mounting it.
        if opt uefi
        then
                local -rx MTOOLS_SKIP_CHECK=1
                truncate --size=$(( esp * bs )) esp.img
                mkfs.vfat -F 32 -n EFI-SYSTEM esp.img
                mmd -i esp.img ::/EFI ::/EFI/BOOT
                mcopy -i esp.img BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI
                dd bs=$bs conv=notrunc if=esp.img of=disk.exe seek=$start
        fi

        # Write the root file system if not using a UEFI ramdisk.
        opt ramdisk && opt uefi ||
        dd bs=$bs conv=notrunc if=final.img of=disk.exe seek=$(( start + esp ))

        # Weave the launcher script around the GPT.
        dd bs=$bs conv=notrunc of=disk.exe << 'EOF'
#!/bin/bash -eu
IMAGE=$(readlink /proc/$$/fd/255)
: << 'THE_PARTITION_TABLE_HAS_ENDED_SO_HERE_IS_THE_SCRIPT_TO_RUN'
EOF
        echo $'\nTHE_PARTITION_TABLE_HAS_ENDED_SO_HERE_IS_THE_SCRIPT_TO_RUN' |
        cat - launch.sh | dd bs=$bs conv=notrunc of=disk.exe seek=34
        chmod 0755 disk.exe
fi

# OPTIONAL (IMAGE)

function double_display_scale() {
        compgen -G 'root/usr/share/kbd/consolefonts/latarcyrheb-sun32.*' ||
        compgen -G 'root/???/*/consolefonts/latarcyrheb-sun32.*' &&
        sed -i -e '/^FONT=/d' root/etc/vconsole.conf &&
        echo 'FONT="latarcyrheb-sun32"' >> root/etc/vconsole.conf

        test -s root/usr/share/glib-2.0/schemas/org.gnome.desktop.interface.gschema.xml &&
        cat << 'EOF' > root/usr/share/glib-2.0/schemas/99_display.scale.gschema.override
[org.gnome.desktop.interface]
scaling-factor=2
[org.gnome.settings-daemon.plugins.xsettings]
overrides={'Gdk/WindowScalingFactor':<2>}
EOF

        return 0
}

function store_home_on_var() {
        opt selinux && (cd root/etc/selinux/targeted/contexts/files
                grep -qs ^/var/home file_contexts.subs_dist ||
                echo /var/home /home >> file_contexts.subs
        )
        mv root/home root/var/home ; ln -fns var/home root/home
        echo 'Q /var/home 0755' > root/usr/lib/tmpfiles.d/home.conf
        if test "x$*" = x+root
        then
                opt selinux && (cd root/etc/selinux/targeted/contexts/files
                        grep -qs ^/var/roothome file_contexts.subs_dist ||
                        echo /var/roothome /root >> file_contexts.subs
                )
                mv root/root root/var/roothome ; ln -fns var/roothome root/root
                cat << 'EOF' > root/usr/lib/tmpfiles.d/root.conf
C /var/roothome 0700 root root - /etc/skel
Z /var/roothome
EOF
        fi
}

function unlock_root() {
        sed -i -e 's/^root:[^:]*/root:/' root/etc/shadow
}

function wine_gog_script() while read
do
        local -A r=()

        while read -rs
        do
                REPLY=${REPLY:1:-1}
                local k=${REPLY%%:*} v=${REPLY#*:}
                k=${k//\"/} ; v=${v#\"} ; v=${v%\"}
                r[${k:-_}]=$v
        done <<< "${REPLY//,/$'\n'}"

        case "${r[valueType]}" in
            string)
                r[valueData]=${r[valueData]//{app\}/Z:${1//\//\\}}
                r[valueType]=REG_SZ
                ;;
            dword)
                r[valueData]=${r[valueData]/#\$/0x}
                r[valueType]=REG_DWORD
                ;;
        esac

        echo wine reg add \
            "'${r[root]//\"/}\\${r[subkey]//\"/}'" \
            /v "${r[valueName]//\"/}" \
            /t "${r[valueType]}" \
            /d "'${r[valueData]}'" /f
done < <(jq -cr '.actions[].install|select(.action=="setRegistry").arguments')
