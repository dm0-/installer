# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=ubuntu [release]=22.04).

# Override the UEFI stub provider for when it was bundled with systemd.
eval "$(declare -f create_buildroot | $sed 's/ systemd-boot-efi / /')"

# Override the resolved provider for when it was bundled with systemd.
eval "$(declare -f install_packages | $sed /systemd-resolved/d)"

[[ ${options[release]} > 21.10 ]] || . "legacy/${options[distro]}21.10.sh"
