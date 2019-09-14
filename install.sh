#!/bin/bash
set -euxo pipefail

# Configure host commands
curl=${CURL:-curl}
dnf=${DNF:-dnf}
gpg=${GPG:-gpg2}
mkdir=${MKDIR:-mkdir}
mktemp=${MKTEMP:-mktemp}
nspawn=${NSPAWN:-systemd-nspawn}
rm=${RM:-rm}
sed=${SED:-sed}
sha256sum=${SHA256SUM:-sha256sum}
sha512sum=${SHA512SUM:-sha512sum}
tar=${TAR:-tar}
uname=${UNAME:-uname}

# Define output directories
output=$($mktemp --directory --tmpdir="$PWD" output.XXXXXXXXXX)
buildroot="$output/buildroot"

. base.sh
${*:+. "$1"}
. "${options[distro]}".sh
${*:+. "$1"}

create_buildroot
customize_buildroot
enter /bin/bash -euxo pipefail << EOF
INSTALL_DISK=${INSTALL_DISK-}  # Let verity know the target disk name.
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

# Write the file system to disk if the PARTUUID was specified.
if test -n "${INSTALL_DISK-}"
then
        test -b "$INSTALL_DISK" || INSTALL_DISK=$(blkid -lo device -t "$INSTALL_DISK")
        dd if="$output/final.img" of="${INSTALL_DISK}" status=progress
fi
