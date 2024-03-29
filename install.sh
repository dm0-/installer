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
declare -A cli_options
declare -a cli_slots
while getopts :BE:IKP:RSUVZa:c:d:hk:o:p:u opt
do
        case $opt in
            B) cli_options[bootable]=1 ;;
            E) cli_options[uefi_path]=$OPTARG ;;
            I) cli_options[install_to_disk]=1 ;;
            K) cli_options[ramdisk]=1 ;;
            P) cli_slots+=(${OPTARG,,}) ;;
            R) cli_options[read_only]=1 ;;
            S) cli_options[squash]=1 ;;
            U) cli_options[uefi]=1 ;;
            V) cli_options[verity]=1 ;;
            Z) cli_options[selinux]=1 ;;
            a) cli_options[adduser]+="${OPTARG//$'\n'/ }"$'\n' ;;
            c) cli_options[signing_cert]=$OPTARG ;;
            d) cli_options[distro]=$OPTARG ;;
            h) usage ; exit 0 ;;
            k) cli_options[signing_key]=$OPTARG ;;
            o) cli_options[${OPTARG%%=*}]=${OPTARG#*=} ;;
            p) cli_options[packages]=$OPTARG ;;
            u) usage | { read -rs ; echo "$REPLY" ; } ; exit 0 ;;
            *) usage 1>&2 ; exit 1 ;;
        esac
done
shift $(( OPTIND - 1 ))

# Load all library files now to combine CLI options with coded settings.
${*:+. "$1"}
imply_options
packages=() slots=()
. "${options[distro]}".sh
[[ -n $* ]] && { . "$1" ; shift ; }
validate_options

# Execute all of the build script functions.
create_working_directory
create_buildroot "$@"
create_root_image
script_with_keydb << EOF
$(declare -p DEFAULT_ARCH disk exclude_paths options packages slots)
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
set_uefi_variables
EOF

# Write the file system to disk at the given partition.
if opt install_to_disk
then
        disk=$($blkid -lo device -t "PARTUUID=$(get_slot_uuid)")
        $dd if="$output/final.img" of="$disk" status=progress
fi

# Save the UEFI binary.
if opt uefi_path
then
        [[ ${options[uefi_path]} == *[^/]/* ]] &&
        $mkdir -p "${options[uefi_path]%/*}"
        $cp -p "$output/BOOT$(archmap_uefi ${options[arch]-}).EFI" \
            "${options[uefi_path]}"
fi
