# SPDX-License-Identifier: GPL-3.0-or-later
DEFAULT_ARCH=$($uname -m)
disk=
exclude_paths=({boot,dev,media,proc,run,srv,sys,tmp}/'*')
packages=()
slots=()

declare -A options
options[distro]=fedora
options[append]=      # The arguments to append to the kernel command-line
options[bootable]=    # Include a kernel and init system to boot the image
options[enforcing]=   # Enforce the SELinux policy instead of being permissive
options[gpt]=         # Create a partitioned GPT disk image
options[hardfp]=      # Use the hard-float ABI for ARMv6 and ARMv7 targets
options[ipe]=         # Write and enforce an IPE policy focused on the root FS
options[loadpin]=     # Enforce LoadPin so the kernel loads files from one FS
options[networkd]=    # Enable minimal DHCP networking without NetworkManager
options[ramdisk]=     # Produce an initrd that sets up the root FS in memory
options[read_only]=   # Use tmpfs in places to make a read-only system usable
options[rootmod]=     # Extra module(s) required by the root disk (e.g. nvme)
options[secureboot]=  # Sign the UEFI executable for Secure Boot verification
options[selinux]=     # Enable SELinux and relabel with the given policy
options[slot]=        # The root partition slot for the build to target
options[squash]=      # Produce a compressed squashfs image
options[uefi]=        # Generate a single UEFI executable containing boot files
options[uefi_vars]=   # List of OVMF files to enroll Secure Boot certificates
options[verity]=      # Prevent file system modification with dm-verity
options[verity_sig]=  # Create and require a verity root hash signature

function usage() {
        echo "Usage: $0 [-BKRSUVZhu] \
[-E <uefi-binary-path>] [[-I] -P <partuuid> ...] \
[-c <pem-certificate> -k <pem-private-key>] \
[-a <userspec>] [-d <distro>] [-o <option>[=<value>]] [-p <package-list>] \
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
  -V    Attach verity hashes to the root file system image (implying -R).
  -Z    Install and enforce targeted SELinux policy, and label the file system.

Install options:
  -E <uefi-binary-path>
        Save the UEFI executable to the given path, which should be on the
        mounted target ESP file system (implying -U).
        Example: -E /boot/EFI/BOOT/BOOTX64.EFI
  -I    Install the file system to disk in the selected root partition slot.
  -P <partuuid>
        Add a root partition slot.  This option can be used multiple times to
        define more root slots.  A specific partition can be selected with the
        slot option, or the first will be used by default.  It configures the
        kernel arguments to select the desired GPT partition UUID as the root
        file system on boot.  If this option is not used, the kernel assumes
        that the root file system is on /dev/sda.
        Example: -P e08ede5f-56d4-4d6d-b8d9-abf7ef5be608

Signing options:
  -c <pem-certificate>
        Provide the PEM certificate for cryptographic authentication purposes
        (e.g. Secure Boot, verity) instead of creating temporary keys for them.
  -k <pem-private-key>
        Provide the PEM private key for cryptographic authentication purposes
        (e.g. Secure Boot, verity) instead of creating temporary keys for them.

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
  -o <option>[=<value>]
        Set an option to the given value, which can be empty to unset.  If the
        equals sign and value are omitted, the option is set to its name.  This
        option can be used multiple times to set more options.
        Example: -o append='quiet splash' -o networkd
  -p <package-list>
        Install the given space-separated list of packages into the image in
        addition to the package set in the system definition file.
        Example: -p 'man-db sudo wget'

Help options:
  -h    Output this help text.
  -u    Output a single line of brief usage syntax."
}

function imply_options() {
        local k ; for k in "${!cli_options[@]}"
        do options[$k]=${cli_options[$k]}
        done
        opt sb_cert && opt sb_key || opt uefi_vars && options[secureboot]=1
        opt verity_cert && opt verity_key && options[verity_sig]=1
        opt secureboot || opt uefi_path && options[uefi]=1
        opt selinux && options[enforcing]=1
        opt verity_sig && options[verity]=1
        opt squash || opt verity && options[read_only]=1
        opt uefi || opt ramdisk || opt loadpin && options[bootable]=1
        opt uefi && options[secureboot]=1  # Always sign the UEFI executable.
        [[ ${options[arch]:-$DEFAULT_ARCH} == armv[67]* ]] && options[hardfp]=1
        opt distro || options[distro]=fedora  # This can't be unset.
}

function validate_options() {
        local k ; for k in "${!cli_options[@]}"
        do options[$k]=${cli_options[$k]}
        done
        slots+=("${cli_slots[@]}")
        # Require both a certificate and key for each signing option.
        for k in sb signing verity
        do
                opt "${k}_cert" && opt "${k}_key"
                opt "${k}_key" && opt "${k}_cert"
                opt "${k}_cert" && [[ -s "${options[${k}_cert]}" ]]
                opt "${k}_key" && [[ -s "${options[${k}_key]}" ]]
        done
        # A partition must be defined for writing the file system to disk.
        opt install_to_disk && (( ${#slots[@]} ))
        # When a root partition slot is chosen, that slot must be defined.
        opt slot && { (( ${#slots[@]} )) ; get_slot_uuid > /dev/null ; }
        # A partition UUID must be set or generated to create a GPT disk image.
        opt gpt && ! opt ramdisk && get_slot_uuid > /dev/null
        # IPE can only trust a root file system on verity or in an initrd.
        opt ipe && { opt ramdisk || opt verity ; }
        # A UEFI executable is required in order to sign it or save it.
        opt secureboot || opt uefi_path && opt uefi
        # SELinux must be enabled to enforce it.
        opt enforcing && opt selinux
        # Map the boolean SELinux option to a default policy name.
        [[ ${options[selinux]-} =~ ^(1|selinux)$ ]] && options[selinux]=targeted
        # The only UEFI variables currently initialized are for Secure Boot.
        opt uefi_vars && opt secureboot
        # A verity signature can't exist without verity.
        opt verity_sig && opt verity
        # Enforce the read-only setting when writing is unsupported.
        opt squash || opt verity && opt read_only
        # The distro must be set or something went wrong.
        opt distro
}

function opt() [[ -n ${options[${*?}]-} ]]

function get_next_slot() if opt slot
then echo -n "${options[slot]}"
elif (( ! ${#slots[@]} ))
then return 1
else
        local device=$($sed -n 's,^\([^ ]*\) / .*,\1,p' < /proc/mounts)
        if [[ $device == /dev/mapper/root ]]  # Assume verity via dm-init.
        then
                local -r mm=$(</sys/block/dm-0/dev)
                device=/dev/$(cd "/sys/dev/block/$mm/slaves" && compgen -G '*')
        fi
        local -r uuid=$($blkid --match-tag=PARTUUID --output=value "$device")
        local -i i ; for (( i = 0 ; i < ${#slots[@]} ; ))
        do [[ ${slots[i++],,} == ${uuid,,} ]] && break
        done &&
        echo -en "\x$(printf '%X' $(( i % ${#slots[@]} + 65 )))"
fi

function get_slot_uuid() {
        local -r slot=${*:-${options[slot]:-A}}
        (( ${#slots[@]} )) || slots+=("$(</proc/sys/kernel/random/uuid)")
        [[ $slot == [A-$(echo -en "\x$(printf '%X' $((${#slots[@]}+64)))")] ]]
        echo -n ${slots[$(printf '%u' "'$slot")-65]}
}

function enter() {
        local -r console=$($nspawn --help |& $sed -n /--console=/p)
        $nspawn \
            --bind="$output:/wd" \
            $([[ -e /dev/kvm ]] && echo --bind=/dev/kvm) \
            ${loop:+--bind="$loop:/dev/loop-root"} \
            --chdir=/wd \
            ${console:+--console=pipe} \
            --directory="$buildroot" \
            --machine="buildroot-${output##*.}" \
            --quiet \
            "$@"
}

function script() {
        enter /bin/bash -euo pipefail -O nullglob -- /dev/stdin "$@" < \
            <([[ $- == *x* ]] && echo "PS4='+\e[34m+\e[0m ' ; set -x" ; exec $cat)
}

function script_with_keydb() { script "$@" << EOF ; }
keydir=\$(mktemp -d) ; (cd "\$keydir"
# Copy any specified signing keys from the host into volatile storage.
$(for app in sb signing verity
do for ext in cert key ; do opt "${app}_$ext" && $cat \
    <(echo "cat << 'EOP-' > ${app/#signing/sign}.${ext/#ce/c}") \
    "${options[${app}_$ext]}" \
    <(echo -e '\nEOP-') ||
: ; done ; done)

# Generate the default signing keys if they weren't supplied.
if [[ ! -s sign.crt || ! -s sign.key ]]
then
        openssl req -batch -nodes -utf8 -x509 -newkey rsa:4096 -sha512 \
            -days 36500 -subj '/CN=Single-use signing key' \
            -outform PEM -out sign.crt -keyout sign.key
        cp -pt /wd sign.crt  # Save the generated certificate for convenience.
fi

# Point any missing application signing keys to the default keys.
for app in sb verity
do
        if [[ ! -s \$app.crt || ! -s \$app.key ]]
        then
                ln -fn sign.crt "\$app.crt"
                ln -fn sign.key "\$app.key"
        fi
done

# Format keys as needed for each application.
cat sign.crt <(echo) sign.key > sign.pem
${options[verity_sig]:+:} false && openssl \
    x509 -in verity.crt -out verity.der -outform DER
if ${options[secureboot]:+:} false
then
        ${options[uefi_vars]:+:} false && {
                echo -n 4e32566d-8e9e-4f52-81d3-5bb9715f9727:
                openssl x509 -outform DER < sb.crt | base64 --wrap=0
        } > sb.oem
        openssl pkcs12 -export \
            -in sb.crt -inkey sb.key \
            -name sb -out sb.p12 -password pass:
        certutil --empty-password -N -d .
        pk12util -W '' -d . -i sb.p12
fi
) ; {
$(</dev/stdin)
} < /dev/null
EOF

# Distros should override these functions.
function create_buildroot() { : ; }
function install_packages() { : ; }
function distro_tweaks() { : ; }
function save_boot_files() { : ; }

# Systems should override these functions.
function initialize_buildroot() { : ; }
function customize_buildroot() { : ; }
function customize() { : ; }

function create_working_directory() {
        output=$($mktemp --directory --tmpdir="$PWD" output.XXXXXXXXXX)
        buildroot="$output/buildroot"
        $mkdir -p "$buildroot"

        # Save a cached script with the given options to rebuild this system.
        if [[ -s install.sh ]]
        then
                $cat << EOF > "$output/rebuild.sh"
#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
$(unset PWD ; shopt -p ; declare -p ; declare -f)
set -"$-"o pipefail
$($sed -n "/^$FUNCNAME$/,$ p" install.sh)
EOF
                $chmod 0755 "$output/rebuild.sh"
        fi

        # Copy host-specific VM firmware files into the directory if given.
        opt uefi_vars || return 0

        local -a args=()
        local list=${options[uefi_vars]}:
        [[ $list == 1: || $list == uefi_vars: ]] ||
        while [[ -n $list && ${#args[@]} -le 4 ]]
        do args+=("${list%%:*}") ; list=${list#*:}
        done

        local -r efi=BOOT$(archmap_uefi ${options[arch]-}).EFI
        local -r root=$buildroot/root/enroll
        $mkdir -p "$root/EFI/BOOT"
        [[ -z ${args[0]-} ]] || $cp "${args[0]}" "$output/vars.fd"
        [[ -z ${args[1]-} ]] || $cp "${args[1]}" "$output/code.fd"
        [[ -z ${args[2]-} ]] || $cp "${args[2]}" "$root/EFI/BOOT/$efi"
        [[ -z ${args[3]-} ]] || $cp "${args[3]}" "$root/EnrollDefaultKeys.efi"
}

function create_root_image() if ! opt read_only && ! opt ramdisk || opt selinux
then
        local -r size=$(opt read_only && echo 10G || echo 3584M)
        $truncate --size="${1:-$size}" "$output/${disk:=ext4.img}"
        declare -g loop=$($losetup --show --find "$output/$disk")
        trap -- '$losetup --detach "$loop"' EXIT
fi

function mount_root() if ! opt read_only && ! opt ramdisk || opt selinux
then
        mkfs.ext4 -m 0 /dev/loop-root
        mount -o X-mount.mkdir /dev/loop-root root
fi

function unmount_root() if ! opt read_only && ! opt ramdisk || opt selinux
then
        e4defrag root
        umount root
        opt read_only && tune2fs -O read-only /dev/loop-root
        e2fsck -Dfy /dev/loop-root || [[ $? -eq 1 ]]
fi

function relabel() if opt selinux
then
        local -r root=$(mktemp --directory --tmpdir="$PWD" relabel.XXXXXXXXXX)
        mkdir -p "$root"/{bin,dev,etc,lib,proc,sys,sysroot}
        ln -fns lib "$root/lib64"
        ln -fst "$root/etc" ../sysroot/etc/selinux

        cat << 'EOF' > "$root/init" ; chmod 0755 "$root/init"
#!/bin/ash -eux
trap -- 'poweroff -f ; exec sleep 60' EXIT
export PATH=/bin
mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount /dev/sda /sysroot
/bin/load_policy -i
policy=$(sed -n 's/^SELINUXTYPE=//p' /etc/selinux/config)
/bin/setfiles -vFr /sysroot \
    "/sysroot/etc/selinux/$policy/contexts/files/file_contexts" /sysroot
rm -f /sysroot/.autorelabel
test -x /bin/mksquashfs && /bin/mksquashfs /sysroot /sysroot/squash.img \
    -noappend -comp zstd -Xcompression-level 22 -wildcards -ef /ef
test -x /bin/mkfs.erofs && IFS=$'\n' && /bin/mkfs.erofs \
    $(while read ; do echo "$REPLY" ; done < /ef) \
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
                local path
                for path in "$disk" "${exclude_paths[@]//\*/[^/]*}"
                do
                        path=${path//+/[+]} ; path=${path//./[.]}
                        echo "--exclude-regex=^${path//\?/[^/]}$"
                done > "$root/ef"
                cp -t "$root/bin" /usr/*bin/mkfs.erofs
        fi

        local cmd
        for cmd in busybox load_policy setfiles
        do
                for cmd in {,/usr}/{,s}bin/"$cmd"
                do cp -t "$root/bin" "$cmd" && break || continue
                done
        done
        for cmd in ash echo mount poweroff rm sed sleep umount
        do ln -fns busybox "$root/bin/$cmd"
        done

        { ldd "$root"/bin/* || : ; } |
        sed -n 's,^[^/]\+\(/[^ ]*\).*,\1,p' | sort -u |
        while read -rs ; do cp -t "$root/lib" "$REPLY" ; done
        cp -pt "$root/lib" /usr/lib*/libgcc_s.so.*

        find "$root" -mindepth 1 -printf '%P\n' |
        cpio -D "$root" -H newc -R 0:0 -o |
        zstd --threads=0 --ultra -22 > relabel.img

        [[ -s vmlinuz.relabel ]] ||
        cp -p /lib/modules/*/vmlinuz vmlinuz.relabel ||
        cp -p /boot/vmlinuz-* vmlinuz.relabel

        umount root
        local -r cores=$([[ -e /dev/kvm ]] && nproc)
        qemu-system-x86_64 -nodefaults -no-reboot -serial stdio < /dev/null \
            ${cores:+-enable-kvm -cpu host -smp cores="$cores"} -m 1G \
            -kernel vmlinuz.relabel -initrd relabel.img \
            -append 'console=ttyS0 enforcing=0 lsm=selinux' \
            -drive file=/dev/loop-root,format=raw,media=disk
        mount /dev/loop-root root
        opt read_only && mv -t . "root/$disk"
        [[ -s root/LABEL-SUCCESS ]] ; rm -f root/LABEL-SUCCESS
fi

function squash() if opt squash && ! opt selinux
then
        local -r IFS=$'\n'
        disk=squash.img
        mksquashfs root "$disk" -noappend -no-xattrs \
            -comp zstd -Xcompression-level 22 \
            -wildcards -ef /dev/stdin <<< "${exclude_paths[*]}"
elif opt ramdisk && ! opt selinux && ! opt verity
then
        [[ -x root/init ]] || if opt read_only
        then cat << 'EOF' > root/init ; chmod 0755 root/init
#!/bin/sh -eux
mountpoint -q /proc || mount -t proc proc /proc
mount -o remount,ro /
exec /usr/lib/systemd/systemd
EOF
        else ln -fns usr/lib/systemd/systemd root/init
        fi
        build_microcode_ramdisk > initrd.img
        find root -mindepth 1 -printf '%P\n' |
        grep -vxf <(
                for path in "${exclude_paths[@]//\*/[^/]*}"
                do path=${path//./\\.} ; echo "${path//\?/[^/]}\(/.*\)\?"
                done
        ) |
        cpio -D root -H newc -o |
        zstd --threads=0 --ultra -22 >> initrd.img
elif opt read_only && ! opt selinux
then
        local -a args ; local path
        disk=erofs.img
        for path in "${exclude_paths[@]//\*/[^/]*}"
        do
                path=${path//+/[+]} ; path=${path//./[.]}
                args+=("--exclude-regex=^${path//\?/[^/]}$")
        done
        mkfs.erofs "${args[@]}" -x-1 "$disk" root
elif ! opt read_only
then
        local path
        for path in "${exclude_paths[@]}"
        do compgen -G "root/$path" || continue
        done | xargs --delimiter='\n' -- rm -fr
fi

function verity() if opt verity
then
        local -ir size=$(stat --format=%s "$disk")
        local -A verity
        local -a opt_params=()
        local root=/dev/sda
        (( !(size % 4096) ))

        (( ${#slots[@]} )) && root=PARTUUID=$(get_slot_uuid)
        opt ramdisk && root=/dev/loop0
        opt verity_sig && opt_params+=(root_hash_sig_key_desc verity:root)

        while read -rs
        do verity[${REPLY%%:*}]=${REPLY#*:}
        done < <(veritysetup format "$disk" verity.img)

        echo > dmsetup.txt \
            root,,,ro,0 $(( size / 512 )) \
            verity ${verity[Hash type]} $root $root \
            ${verity[Data block size]} ${verity[Hash block size]} \
            ${verity[Data blocks]} $(( ${verity[Data blocks]} + 1 )) \
            ${verity[Hash algorithm]} ${verity[Root hash]} \
            ${verity[Salt]} "${#opt_params[@]}" "${opt_params[@]}"

        opt verity_sig && openssl smime -sign \
            -inkey "$keydir/verity.key" -signer "$keydir/verity.crt" \
            -binary -in <(echo -n ${verity[Root hash]}) \
            -noattr -nocerts -out verity.sig -outform DER

        cat "$disk" verity.img > final.img
else [[ -z $disk ]] || ln -fn "$disk" final.img
fi

function kernel_cmdline() if opt bootable
then
        local dmsetup=dm-mod.create
        local root=/dev/sda
        local type=ext4

        opt ramdisk && dmsetup=DVR
        opt verity_sig && dmsetup=DVR  # Skip dm-init for userspace as a hack.

        (( ${#slots[@]} )) && root=PARTUUID=$(get_slot_uuid)
        opt ramdisk && root=/dev/loop0
        opt verity && root=/dev/dm-0

        opt read_only && type=erofs
        opt squash && type=squashfs

        echo > kernel_args.txt \
            $(opt read_only && echo ro || echo rw) \
            $([[ -s final.img ]] && echo "root=$root" "rootfstype=$type") \
            $(opt selinux && echo security=selinux || echo selinux=0) \
            ${options[loadpin]:+loadpin.enforce=1} \
            ${options[verity]:+"$dmsetup=\"$(<dmsetup.txt)\""} \
            ${options[verity_sig]:+dm-verity.require_signatures=1} \
            ${options[append]-}
fi

function build_microcode_ramdisk() if [[ ${options[arch]:-$DEFAULT_ARCH} == *[3-6x]86* ]]
then
        local -r dir=/root/earlycpio/kernel/x86/microcode
        mkdir -p "$dir"
        compgen -G '/lib/firmware/amd-ucode/*.bin' > /dev/null &&
        cat /lib/firmware/amd-ucode/*.bin > "$dir/AuthenticAMD.bin"
        compgen -G '/lib/firmware/intel-ucode/*' > /dev/null &&
        cat /lib/firmware/intel-ucode/* > "$dir/GenuineIntel.bin"
        (
                cd "${dir%/kernel/*}" ; IFS=$'\n'
                f=(kernel{,/x86{,/microcode}} kernel/x86/microcode/*.bin)
                [[ ${#f[@]} -lt 4 ]] || exec cpio -H newc -o <<< "${f[*]}"
        )
fi

function build_systemd_ramdisk() if opt ramdisk
then
        [[ -s $1 ]] && local -r base=$1 ||
        { local -r base=/root/initrd.img ; dracut --force "$base" "$1" ; }
        local -r root=$(mktemp --directory --tmpdir="$PWD" ramdisk.XXXXXXXXXX)
        mkdir -p "$root/usr/lib/systemd/system/dev-loop0.device.requires"
        cat << EOF > "$root/usr/lib/systemd/system/losetup-root.service"
[Unit]
DefaultDependencies=no
After=systemd-tmpfiles-setup-dev.service
Requires=systemd-tmpfiles-setup-dev.service
[Service]
ExecStart=/usr/sbin/losetup --find${options[read_only]:+ --read-only} /root.img
RemainAfterExit=yes
Type=oneshot
EOF
        ln -fst "$root/usr/lib/systemd/system/dev-loop0.device.requires" ../losetup-root.service
        ln -fn final.img "$root/root.img"
        find "$root" -mindepth 1 -printf '%P\n' |
        cpio -D "$root" -H newc -R 0:0 -o |
        zstd --threads=0 --ultra -22 | cat "$base" - > initrd.img
elif [[ -s $1 ]]
then cp -p "$1" initrd.img
else dracut --force initrd.img "$1"
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
        exclude_paths+=(home/'*')

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

        local name ; for name in system-auth common-session
        do
                [[ -s root/etc/pam.d/$name ]] &&
                echo >> "root/etc/pam.d/$name" \
                    'session     optional      pam_mkhomedir.so' &&
                break || continue
        done

        mkdir -p root/usr/lib/tmpfiles.d
        cat << 'EOF' > root/usr/lib/tmpfiles.d/home-root.conf
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
Before=local-fs.target
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

        opt selinux && local policy &&
        for policy in root/etc/selinux/*/contexts/files
        do echo /run/etcgo/overlay /etc >> "$policy/file_contexts.subs_dist"
        done

        if [[ -x root/usr/bin/git ]]
        then
                cat << 'EOF' > root/usr/lib/systemd/system/etcgo.service
[Unit]
Description=Restore the /etc overlay from Git
DefaultDependencies=no
RefuseManualStop=yes

[Service]
ExecStartPre=/bin/bash -c "if ! compgen -G '*' > /dev/null ; then \
git -c init.defaultBranch=master init --bare ; \
echo 'System configuration overlay tracker' > description ; \
echo -e '[user]\n\tname = root\n\temail = root@localhost' >> config ; \
cp -pt hooks /usr/share/etcgo/post-checkout ; \
exec git --work-tree=/ commit --allow-empty --message='Repository created' ; \
fi"
ExecStartPre=-/bin/rm -fr worktrees
ExecStart=/usr/bin/git worktree add --force -B master ../../../run/etcgo/overlay master
RemainAfterExit=yes
RuntimeDirectory=etcgo etcgo/overlay etcgo/wd
RuntimeDirectoryPreserve=yes
StateDirectory=etcgo
StateDirectoryMode=0700
Type=oneshot
WorkingDirectory=/var/lib/etcgo
EOF
                mkdir -p root/usr/share/etcgo
                cat << 'EOF' > root/usr/share/etcgo/post-checkout
#!/bin/bash -eu
selinuxenabled &> /dev/null && restorecon -FR . || :
[[ ! -s .gitattributes ]] || while read -a attrs
do
        [[ -n ${attrs-} && $attrs != \#* ]] || continue

        args=(-path)
        [[ $attrs == /* ]] && args+=(".$attrs") || args+=("*/$attrs")

        for attr in "${attrs[@]:1}"
        do
                case $attr in
                    owner=*) args+=(-exec chown "${attr#*=}" {} +) ;;
                    group=*) args+=(-exec chgrp "${attr#*=}" {} +) ;;
                    mode=*) args+=(-exec chmod "${attr#*=}" {} +) ;;
                esac
        done

        find . "${args[@]}" > /dev/null
done < .gitattributes
EOF
                chmod 0755 root/usr/share/etcgo/post-checkout
                rm -f root/usr/lib/systemd/system/etc-overlay-setup.service
                sed -i -e s/-overlay-setup/go/ root/usr/lib/systemd/system/etc.mount
        fi
fi

eval "function configure_packages() {
$($cat configure.pkg.d/[!.]*.sh 0<&-)
return 0 ; }"

function configure_system() {
        opt read_only && exclude_paths+=(lost+found)

        sed -i -e 's/^root:[^:]*/root:*/' root/etc/shadow

        [[ -s root/etc/sudoers ]] &&
        sed -i -e '/%wheel/{s/^[# ]*/# /;/NOPASSWD/s/^[# ]*//;}' root/etc/sudoers

        [[ -s root/etc/profile ]] &&
        sed -i -e 's/ umask 0[0-7]*/ umask 022/' root/etc/profile

        local -ar modes=(disabled permissive enforcing)
        [[ -s root/etc/selinux/config ]] &&
        sed -i \
            -e "/^SELINUX=/s/=.*/=${modes[0${options[selinux]:+1+0${options[enforcing]:+1}}]}/" \
            -e "/^SELINUXTYPE=/s/=.*/=${options[selinux]:-targeted}/" \
            root/etc/selinux/config

        mkdir -p root/etc/skel
        cat << 'EOF' >> root/etc/skel/.bashrc
function defer() {
        local -r cmd="$(trap -p EXIT)"
        eval "trap -- '$*;'${cmd:8:-5} EXIT"
}
EOF

        [[ -d root/usr/lib/locale/en_US.utf8 ]] ||
        localedef --list-archive root/usr/lib/locale/locale-archive |& grep -Fqsx en_US.utf8 &&
        echo 'LANG="en_US.UTF-8"' > root/etc/locale.conf

        ln -fns ../usr/share/zoneinfo/America/New_York root/etc/localtime

        # WORKAROUNDS

        mkdir -p root/usr/lib/tmpfiles.d
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

        # Update portage environment configuration.
        [[ -x /usr/sbin/env-update && -d root/etc/env.d ]] &&
        ROOT=root env-update --no-ldconfig

        # Regenerate gsettings defaults.
        [[ -d root/usr/share/glib-2.0/schemas ]] &&
        glib-compile-schemas root/usr/share/glib-2.0/schemas

        # Run depmod when kernel modules are installed.
        dir=$(compgen -G 'root/lib/modules/*') &&
        depmod --basedir=root "${dir##*/}"

        # Move the giant hardware database to /usr when udev is installed.
        rm -f root/etc/udev/hwdb.bin
        [[ -x /bin/systemd-hwdb ]] && systemd-hwdb --root=root --usr update

        # Create users now so it doesn't need to happen during boot.
        systemd-sysusers --root=root

        # Create users from options after system groups were created.
        opt adduser && (IFS=$'\n'
                for spec in ${options[adduser]}
                do
                        spec+=::::
                        name=${spec%%:*}
                        uid=${spec#*:} uid=${uid%%:*}
                        groups=${spec#*:*:} groups=${groups%%:*}
                        gecos=${spec#*:*:*:} gecos=${gecos%%:*}
                        useradd --prefix /wd/root \
                            ${gecos:+--comment="$gecos"} \
                            ${groups:+--groups="$groups"} \
                            ${uid:+--uid="$uid"} \
                            --create-home --password= "$name"
                done
        )

        # Work around systemd-repart not finding the storage device.
        opt ramdisk || if compgen -G 'root/usr/lib/repart.d/*.conf' &>/dev/null
        then
                local -r gendir=/usr/lib/systemd/system-generators
                mkdir -p "root$gendir"
                echo '#!/bin/bash -eu' > "root$gendir/repart-disk-wait"
                if opt verity
                then cat << 'EOF'
table=( $(dmsetup table "$(findmnt --noheadings --output=source --raw /)") )
[[ ${table[2]} == verity ]] && mm=${table[4]} || exit 0  # not verity root
EOF
                else echo 'mm=$(findmnt --noheadings --output=maj:min --raw /)'
                fi >> "root$gendir/repart-disk-wait"
                cat << 'EOF' >> "root$gendir/repart-disk-wait"
[[ -e /sys/dev/block/$mm/partition ]] || exit 0  # not partitioned
part=$(sed -n s,^DEVNAME=,/dev/,p "/sys/dev/block/$mm/uevent")
dev=/dev/$(lsblk --nodeps --noheadings --output=PKNAME "$part")
[[ -b $dev ]] || exit 0  # failed to find the partition's parent device
unit=$(systemd-escape --path "$dev").device
mkdir -p /run/systemd/system/systemd-repart.service.d
echo -e "[Unit]\nAfter=$unit\nWants=$unit" \
    > /run/systemd/system/systemd-repart.service.d/wait.conf
EOF
                chmod 0755 "root$gendir/repart-disk-wait"
        fi

        # Save os-release outside the image after all customizations.
        if [[ -s root/etc/os-release ]]
        then cp -pt . root/etc/os-release
        elif [[ -s root/usr/lib/os-release ]]
        then cp -pt . root/usr/lib/os-release
        fi
}

function produce_uefi_exe() if opt uefi
then
        local -r arch=$(archmap_uefi ${options[arch]-})
        local -r dtb=$([[ -s devicetree.dtb ]] && echo devicetree.dtb)
        local -r initrd=$([[ -s initrd.img ]] && echo initrd.img)
        local -r kargs=$([[ -s kernel_args.txt ]] && echo kernel_args.txt)
        local -r linux=$([[ -s vmlinux ]] && echo vmlinux || echo vmlinuz)
        local -r logo=$([[ -s logo.bmp ]] && echo logo.bmp)
        local -r osrelease=$([[ -s os-release ]] && echo os-release)
        local -r stub=/usr/lib/systemd/boot/efi/linux${arch,,}.efi.stub
        local -ir align=$(objdump -p "$stub" | awk '$1=="SectionAlignment"{print strtonum("0x"$2)}')
        local -i end=$(objdump -h "$stub" | awk 'NF==7{e=strtonum("0x"$3)+strtonum("0x"$4)}END{print e}') t

        objcopy \
            ${osrelease:+--add-section .osrel="$osrelease" --change-section-vma .osrel=$((end+=align-end%align,t=end,end+=$(stat -Lc%s "$osrelease"),t))} \
            ${kargs:+--add-section .cmdline="$kargs" --change-section-vma .cmdline=$((end+=align-end%align,t=end,end+=$(stat -Lc%s "$kargs"),t))} \
            ${logo:+--add-section .splash="$logo" --change-section-vma .splash=$((end+=align-end%align,t=end,end+=$(stat -Lc%s "$logo"),t))} \
            ${dtb:+--add-section .dtb="$dtb" --change-section-vma .dtb=$((end+=align-end%align,t=end,end+=$(stat -Lc%s "$dtb"),t))} \
            ${linux:+--add-section .linux="$linux" --change-section-vma .linux=$((end+=align-end%align,t=end,end+=$(stat -Lc%s "$linux"),t))} \
            ${initrd:+--add-section .initrd="$initrd" --change-section-vma .initrd=$((end+=align-end%align,t=end,end+=$(stat -Lc%s "$initrd"),t))} \
            "$stub" unsigned.efi

        if opt secureboot
        then
                pesign --certdir="$keydir" --certificate=sb --force \
                    --in=unsigned.efi --out="BOOT$arch.EFI" --sign
        else ln -fn unsigned.efi "BOOT$arch.EFI"
        fi
fi

function partition() if opt gpt
then
        local -r efi=BOOT$(archmap_uefi ${options[arch]-}).EFI
        local -ir bs=512 start=2048
        local -i esp=${options[esp_size]:-0} size=0

        # The disk image has a root file system when not using a UEFI ramdisk.
        opt ramdisk && opt uefi || size=$(stat --format=%s final.img)
        size=$(( size / bs + !!(size % bs) ))

        # The image needs an ESP for the UEFI binary, 260MiB minimum size.
        opt uefi && ((!esp)) && esp=$(( 4194304 + $(stat --format=%s "$efi") ))
        ! opt esp_size && (( esp && esp < 272629760 )) && esp=272629760
        esp=$(( ((esp >> 20) + !!(esp & 0xFFFFF)) * 1048576 / bs ))

        # Format a disk image with the appropriate partition layout.
        truncate --size=$(( (start + esp + size + 33) * bs )) gpt.img
        {
                echo 'label: gpt'
                (( esp )) && echo \
                    size="$esp", \
                    type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, \
                    'name="EFI System Partition"'
                opt ramdisk && opt uefi || echo \
                    size="$size", \
                    type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, \
                    ${slots[*]:+uuid=$(get_slot_uuid),} \
                    name="ROOT-${options[slot]:-A}"
        } | sfdisk --force gpt.img

        # Create the ESP without mounting it.
        if opt uefi
        then
                local -rx MTOOLS_SKIP_CHECK=1
                local -r esp_image="gpt.img@@$(( start * bs ))"
                mkfs.vfat --offset=$start -F 32 -n EFI-SYSTEM -S $bs \
                    gpt.img $(( esp * bs >> 10 ))
                mmd -i $esp_image ::/EFI ::/EFI/BOOT
                mcopy -i $esp_image "$efi" "::/EFI/BOOT/$efi"
        fi

        # Write the root file system if not using a UEFI ramdisk.
        opt ramdisk && opt uefi ||
        dd bs=$bs conv=notrunc if=final.img of=gpt.img seek=$(( start + esp ))

        # Weave the launcher script around the GPT.
        if [[ -s launch.sh ]]
        then
                dd bs=$bs conv=notrunc of=gpt.img << 'EOF'
#!/bin/bash -eu
IMAGE=$(readlink /proc/$$/fd/255)
: << 'THE_PARTITION_TABLE_HAS_ENDED_SO_HERE_IS_THE_SCRIPT'
EOF
                echo $'\nTHE_PARTITION_TABLE_HAS_ENDED_SO_HERE_IS_THE_SCRIPT' |
                cat - launch.sh | dd bs=$bs conv=notrunc of=gpt.img seek=34
                chmod 0755 gpt.img
        fi
fi

function set_uefi_variables() if opt uefi_vars
then
        local -Ar defaults=(
                [vars]=/usr/share/edk2/ovmf/OVMF_VARS.fd
                [code]=/usr/share/edk2/ovmf/OVMF_CODE.secboot.fd
                [shell]=/usr/share/edk2/ovmf/Shell.efi
                [enroll]=/usr/share/edk2/ovmf/EnrollDefaultKeys.efi
        )
        local -r efi=BOOT$(archmap_uefi ${options[arch]-}).EFI
        local -r root=/root/enroll
        [[ -s vars.fd ]] || cp "${defaults[vars]:?}" vars.fd
        [[ -s code.fd ]] || cp "${defaults[code]:?}" code.fd
        [[ -s $root/EFI/BOOT/$efi ]] ||
        ln -fns "../../../..${defaults[shell]:?}" "$root/EFI/BOOT/$efi"
        [[ -s $root/EnrollDefaultKeys.efi ]] ||
        ln -fns "../..${defaults[enroll]:?}" "$root/EnrollDefaultKeys.efi"

        cat << 'EOF' > "$root/startup.nsh"
@echo -off
EnrollDefaultKeys.efi --no-default
if %lasterror% == 0 then
        reset -s "Successfully enrolled Secure Boot certs"
else
        reset -s "Failed to enroll Secure Boot certs"
endif
EOF

        timeout 3m qemu-system-x86_64 -nodefaults -nographic -no-reboot \
            -machine q35 -serial stdio < /dev/null \
            -drive file=code.fd,format=raw,if=pflash,read-only=on \
            -drive file=vars.fd,format=raw,if=pflash \
            -drive file="fat:ro:$root",format=raw,if=virtio,media=disk,read-only=on \
            -smbios type=11,path="$keydir/sb.oem" |&
        grep -Fqs 'Successfully enrolled Secure Boot certs'
fi

function archmap_go() case ${*:-$DEFAULT_ARCH} in
    aarch64)     echo arm64 ;;
    arm*)        echo arm ;;
    i[3-6]86)    echo 386 ;;
    powerpc64)   echo ppc64 ;;
    powerpc64le) echo ppc64le ;;
    riscv64)     echo riscv64 ;;
    x86_64)      echo amd64 ;;
    *) return 1 ;;
esac

function archmap_kernel() case ${*:-$DEFAULT_ARCH} in
    aarch64)  echo arm64 ;;
    arm*)     echo arm ;;
    i[3-6]86) echo x86 ;;
    powerpc*) echo powerpc ;;
    riscv*)   echo riscv ;;
    sh*)      echo sh ;;
    x86_64)   echo x86 ;;
    *) return 1 ;;
esac

function archmap_llvm() case ${*:-$DEFAULT_ARCH} in
    aarch64)  echo AArch64 ;;
    arm*)     echo ARM ;;
    i[3-6]86) echo X86 ;;
    powerpc*) echo PowerPC ;;
    riscv64)  echo RISCV ;;
    x86_64)   echo X86 ;;
    *) return 1 ;;
esac

function archmap_rust() case ${*:-$DEFAULT_ARCH} in
    aarch64)     echo aarch64-unknown-linux-gnu ;;
    armv4t*)     echo armv4t-unknown-linux-gnueabi ;;
    armv5te*)    echo armv5te-unknown-linux-gnueabi ;;
    armv6*)      echo arm-unknown-linux-gnueabi${options[hardfp]:+hf} ;;
    armv7*)      echo armv7-unknown-linux-gnueabi${options[hardfp]:+hf} ;;
    i386)        echo i386-unknown-linux-gnu ;;
    i486)        echo i486-unknown-linux-gnu ;;
    i586)        echo i586-unknown-linux-gnu ;;
    i686)        echo i686-unknown-linux-gnu ;;
    powerpc)     echo powerpc-unknown-linux-gnu ;;
    powerpc64)   echo powerpc64-unknown-linux-gnu ;;
    powerpc64le) echo powerpc64le-unknown-linux-gnu ;;
    riscv64)     echo riscv64gc-unknown-linux-gnu ;;
    x86_64)      echo x86_64-unknown-linux-gnu ;;
    *) return 1 ;;
esac

function archmap_uefi() case ${*:-$DEFAULT_ARCH} in
    aarch64)  echo AA64 ;;
    arm*)     echo ARM ;;
    i[3-6]86) echo IA32 ;;
    ia64)     echo IA64 ;;
    riscv32)  echo RISCV32 ;;
    riscv64)  echo RISCV64 ;;
    riscv128) echo RISCV128 ;;
    x86_64)   echo X64 ;;
    *) return 1 ;;
esac

# OPTIONAL (IMAGE)

function store_home_on_var() {
        opt selinux && local policy &&
        for policy in root/etc/selinux/*/contexts/files
        do
                grep -qs ^/var/home "$policy/file_contexts.subs_dist" ||
                echo /var/home /home >> "$policy/file_contexts.subs_dist"
        done
        mv root/home root/var/home ; ln -fns var/home root/home
        echo 'Q /var/home 0755' > root/usr/lib/tmpfiles.d/home.conf
        if [[ $* = +root ]]
        then
                opt selinux && for policy in root/etc/selinux/*/contexts/files
                do
                        grep -qs ^/var/roothome "$policy/file_contexts.subs_dist" ||
                        echo /var/roothome /root >> "$policy/file_contexts.subs_dist"
                done
                mv root/root root/var/roothome ; ln -fns var/roothome root/root
                cat << 'EOF' > root/usr/lib/tmpfiles.d/home-root.conf
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
                k=${k//\"} ; v=${v#\"} ; v=${v%\"}
                r[${k:-_}]=$v
        done <<< "${REPLY//,/$'\n'}"

        case ${r[valueType]} in
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
            "'${r[root]//\"}\\${r[subkey]//\"}'" \
            /v "'${r[valueName]//\"}'" \
            /t "${r[valueType]}" \
            /d "'${r[valueData]}'" /f
done < <(jq -cr '.actions[].install|select(.action=="setRegistry").arguments')
