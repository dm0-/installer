#!/bin/bash -e
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
shopt -s nullglob

# Configure required host commands via environment variables.
blkid=${BLKID:-blkid}
cat=${CAT:-cat}
chmod=${CHMOD:-chmod}
cp=${CP:-cp}
curl=${CURL:-curl}
dd=${DD:-dd}
gpg=${GPG:-gpg2}
ln=${LN:-ln}
losetup=${LOSETUP:-losetup}
mkdir=${MKDIR:-mkdir}
mktemp=${MKTEMP:-mktemp}
mv=${MV:-mv}
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
while getopts :BE:IKP:RSUVZa:c:d:hk:o:p:u opt
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
            a) options[adduser]+="${OPTARG//$'\n'/ }"$'\n' ;;
            c) options[signing_cert]=$OPTARG ;;
            d) options[distro]=$OPTARG ;;
            h) usage ; exit 0 ;;
            k) options[signing_key]=$OPTARG ;;
            o) [[ $OPTARG == *=* ]] ; options[${OPTARG%%=*}]=${OPTARG#*=} ;;
            p) options[packages]=$OPTARG ;;
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

create_buildroot "$@"
create_root_image
script_with_keydb << EOF
$(declare -p DEFAULT_ARCH disk exclude_paths options packages)
$(declare -f)
mount_root
customize_buildroot
install_packages \${options[packages]-}
tmpfs_var
tmpfs_home
overlay_etc
configure_packages
configure_system
distro_tweaks
customize
finalize_packages
relabel
squash
unmount_root
verity
kernel_cmdline
save_boot_files
produce_uefi_exe
partition
EOF

# Write the file system to disk at the given partition.
if opt install_to_disk
then
        disk=$($blkid -lo device -t "PARTUUID=${options[partuuid]}")
        $dd if="$output/final.img" of="$disk" status=progress
fi

# Save the UEFI binary.
if opt uefi_path
then
        $mkdir -p "${options[uefi_path]%/*}"
        $cp -p "$output/BOOTX64.EFI" "${options[uefi_path]}"
fi
