# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=ubuntu [release]=20.04).

# Override default OVMF paths.
eval "$(declare -f set_uefi_variables | $sed s/_4M//g)"

[[ ${options[release]} == 20.04 ]]
