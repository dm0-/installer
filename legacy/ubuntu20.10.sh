# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=ubuntu [release]=20.10).

# Override ramdisk creation since the kernel is too old to support zstd.
eval "$(declare -f create_buildroot | $sed 's/ zstd//'
declare -f configure_initrd_generation | $sed /compress=/d
declare -f relabel squash build_systemd_ramdisk |
$sed 's/zstd --[^|>]*/xz --check=crc32 -9e /')"

# Override ESP creation to support old dosfstools that can't use offsets.
eval "$(declare -f partition | $sed '/^ *if opt uefi/,/^ *fi/{
/esp_image=/s/=.*/=esp.img ; truncate --size=$(( esp * bs )) $esp_image/
s/ --offset=[^ ]* / /;s/ gpt.img / $esp_image /
/^ *fi/idd bs=$bs conv=notrunc if=$esp_image of=gpt.img seek=$start
}')"

# Override variable generation to use the old QEMU bare SMBIOS argument.
eval "$(declare -f set_uefi_variables | $sed -e '/timeout/i\
cat <(echo -en "\\x0B\\x05\\x34\\x12\\x01") "$keydir/sb.oem" <(echo -en "\\0\\0") > "$keydir/sb.smbios"
s/type=11,path\(=\S*\)oem/file\1smbios/')"

[[ ${options[release]} > 20.04 ]] || . "legacy/${options[distro]}20.04.sh"
