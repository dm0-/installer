# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=ubuntu [release]=21.10).

# Point EOL releases at the archive repository server.
[[ ${options[release]} == 20.04 ]] ||
eval "$(declare -f create_buildroot | $sed '/fix-apt/i\
$sed -i -e "/ubuntu.com/s,://[a-z]*,://old-releases," "$buildroot/etc/apt/sources.list"'
declare -f install_packages | $sed -e 's,://archive,://old-releases,')"

# Verify old detached signatures.
[[ ${options[release]} == 20.04 ]] || eval "$(
declare -f create_buildroot | $sed '/SUMS/{p;s/.gpg//g;};s/.gpg /{,.gpg} /'
declare -f verify_distro | $sed \
    -e 's/--decrypt[^|]*|/--verify "$2" "$1"/;s/.sed[^|]*|/\n/' \
    -e 's/\(sha.*\)2"/\13"/;s,<.*/stdin,$sed -n "s/ .*root.tar.xz$//p" "$1",')"

# Override previous UEFI logo edits.
eval "$(declare -f save_boot_files | $sed \
    -e 's,/g,&;/<svg/s/>/ viewBox="0 0 22 22">/,' \
    -e "s/convert.*svg/& -color-matrix '0 1 0 0 0 0 1 0 0 0 0 1 1 0 0 0'/")"

[[ ${options[release]} > 20.10 ]] || . "legacy/${options[distro]}20.10.sh"
