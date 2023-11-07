# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=ubuntu [release]=22.10).

# Point EOL releases at the archive repository server.
[[
        ${options[release]#[0-9][0-9].} == 04 &&  # LTS are April releases...
        $(( ${options[release]%%.*} & 1 )) -eq 0 &&  # every other year...
        ${options[release]%%.*} -ge 20  # with the oldest supported from 2020.
]] || eval "$(declare -f create_buildroot | $sed '/fix-apt/i\
$sed -i -e "/ubuntu.com/s,://[a-z]*,://old-releases," "$buildroot/etc/apt/sources.list"'
declare -f install_packages | $sed -e 's,://archive,://old-releases,')"

[[ ${options[release]} > 22.04 ]] || . "legacy/${options[distro]}22.04.sh"
