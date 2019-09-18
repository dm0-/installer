#!/bin/bash -e
set -euo pipefail

# Configure required host commands via environment variables.
blkid=${BLKID:-blkid}
cp=${CP:-cp}
curl=${CURL:-curl}
dd=${DD:-dd}
gpg=${GPG:-gpg2}
losetup=${LOSETUP:-losetup}
mkdir=${MKDIR:-mkdir}
mktemp=${MKTEMP:-mktemp}
nspawn=${NSPAWN:-systemd-nspawn}
rm=${RM:-rm}
sed=${SED:-sed}
sha256sum=${SHA256SUM:-sha256sum}
sha512sum=${SHA512SUM:-sha512sum}
tar=${TAR:-tar}
truncate=${TRUNCATE:-truncate}
uname=${UNAME:-uname}

# Load basic functions.
. base.sh

# Parse command-line options.
while getopts :BE:IKP:RSUVZhu opt
do
        case "$opt" in
            B) options[bootable]=1 ;;
            E) options[uefi_path]=$OPTARG ;;
            I) options[install_to_disk]=1 ;;
            K) options[ramdisk]=1 ;;
            P) options[partuuid]=${OPTARG,,} ;;
            R) options[read_only]=1 ;;
            S) options[squash]=1 ;;
            U) options[uefi]=1 ;;
            V) options[verity]=1 ;;
            Z) options[selinux]=1 ;;
            h) usage ; exit 0 ;;
            u) usage | { read -rs ; echo "$REPLY" ; } ; exit 0 ;;
            *) usage 1>&2 ; exit 1 ;;
        esac
done
shift $(( OPTIND - 1 ))

# Load all library files now to combine CLI options with coded settings.
${*:+. "$1"}
imply_options
. "${options[distro]}".sh
test -n "$*" && { . "$1" ; shift ; }
validate_options

# Define output directories
output=$($mktemp --directory --tmpdir="$PWD" output.XXXXXXXXXX)
buildroot="$output/buildroot"

create_buildroot
customize_buildroot "$@"
opt squash || create_root_image
enter /bin/bash -euxo pipefail << EOF
$(declare -p disk exclude_paths options packages)
$(declare -f)
opt squash || mount_root
install_packages
configure_dhcp
opt iptables && configure_iptables
opt read_only && tmpfs_var
opt read_only && tmpfs_home
opt read_only && overlay_etc
local_login
configure_system
distro_tweaks
customize
opt bootable && save_boot_files
opt selinux && relabel
opt squash && squash || unmount_root
opt verity && verity || ln -f "$disk" final.img
opt ramdisk && build_ramdisk
opt uefi && produce_uefi_exe
opt nspawn && produce_nspawn_exe
:
EOF

# Save the UEFI binary.
if opt uefi_path
then
        $mkdir -p "${options[uefi_path]%/*}"
        $cp -p "$output/BOOTX64.EFI" "${options[uefi_path]}"
fi

# Write the file system to disk at the given partition.
if opt install_to_disk
then
        disk=$($blkid -lo device -t "PARTUUID=${options[partuuid]}")
        $dd if="$output/final.img" of="$disk" status=progress
fi
