# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=fedora [release]=33).

packages=(glibc-minimal-langpack)

# Override UEFI splash screen creation for the old logo.
eval "$(declare -f save_boot_files | $sed "s|\(convert.* \)\([^ ]*svg\)|sed \
'/id=.g524[17]/,/[/]/{/</,/>/d;}' \2 > /root/logo.svg \&\& \1/root/logo.svg|")"

# Override ESP creation to support old dosfstools that can't use offsets.
eval "$(declare -f partition | $sed '/^ *if opt uefi/,/^ *fi/{
/esp_image=/s/=.*/=esp.img ; truncate --size=$(( esp * bs )) $esp_image/
s/ --offset=[^ ]* / /;s/ gpt.img / $esp_image /
/^ *fi/idd bs=$bs conv=notrunc if=$esp_image of=gpt.img seek=$start
}')"

# Override UEFI variable generation to use the old QEMU bare SMBIOS argument.
eval "$(declare -f set_uefi_variables | $sed -e '/timeout/i\
cat <(echo -en "\\x0B\\x05\\x34\\x12\\x01") "$keydir/sb.oem" <(echo -en "\\0\\0") > "$keydir/sb.smbios"
s/type=11,path\(=\S*\)oem/file\1smbios/')"

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import
        $gpg --verify "$1"
        [[ $($sha256sum "$2") == $($sed -n '/=/{s/.* //p;q;}' "$1")\ * ]]
} << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBF4wBvsBEADQmcGbVUbDRUoXADReRmOOEMeydHghtKC9uRs9YNpGYZIB+bie
bGYZmflQayfh/wEpO2W/IZfGpHPL42V7SbyvqMjwNls/fnXsCtf4LRofNK8Qd9fN
kYargc9R7BEz/mwXKMiRQVx+DzkmqGWy2gq4iD0/mCyf5FdJCE40fOWoIGJXaOI1
Tz1vWqKwLS5T0dfmi9U4Tp/XsKOZGvN8oi5h0KmqFk7LEZr1MXarhi2Va86sgxsF
QcZEKfu5tgD0r00vXzikoSjn3qA5JW5FW07F1pGP4bF5f9J3CZbQyOjTSWMmmfTm
2d2BURWzaDiJN9twY2yjzkoOMuPdXXvovg7KxLcQerKT+FbKbq8DySJX2rnOA77k
UG4c9BGf/L1uBkAT8dpHLk6Uf5BfmypxUkydSWT1xfTDnw1MqxO0MsLlAHOR3J7c
oW9kLcOLuCQn1hBEwfZv7VSWBkGXSmKfp0LLIxAFgRtv+Dh+rcMMRdJgKr1V3FU+
rZ1+ZAfYiBpQJFPjv70vx+rGEgS801D3PJxBZUEy4Ic4ZYaKNhK9x9PRQuWcIBuW
6eTe/6lKWZeyxCumLLdiS75mF2oTcBaWeoc3QxrPRV15eDKeYJMbhnUai/7lSrhs
EWCkKR1RivgF4slYmtNE5ZPGZ/d61zjwn2xi4xNJVs8q9WRPMpHp0vCyMwARAQAB
tDFGZWRvcmEgKDMzKSA8ZmVkb3JhLTMzLXByaW1hcnlAZmVkb3JhcHJvamVjdC5v
cmc+iQI4BBMBAgAiBQJeMAb7AhsPBgsJCAcDAgYVCAIJCgsEFgIDAQIeAQIXgAAK
CRBJ/XdJlXD/MZm2D/9kriL43vd3+0DNMeA82n2v9mSR2PQqKny39xNlYPyy/1yZ
P/KXoa4NYSCA971LSd7lv4n/h5bEKgGHxZfttfOzOnWMVSSTfjRyM/df/NNzTUEV
7ORA5GW18g8PEtS7uRxVBf3cLvWu5q+8jmqES5HqTAdGVcuIFQeBXFN8Gy1Jinuz
AH8rJSdkUeZ0cehWbERq80BWM9dhad5dW+/+Gv0foFBvP15viwhWqajr8V0B8es+
2/tHI0k86FAujV5i0rrXl5UOoLilO57QQNDZH/qW9GsHwVI+2yecLstpUNLq+EZC
GqTZCYoxYRpl0gAMbDLztSL/8Bc0tJrCRG3tavJotFYlgUK60XnXlQzRkh9rgsfT
EXbQifWdQMMogzjCJr0hzJ+V1d0iozdUxB2ZEgTjukOvatkB77DY1FPZRkSFIQs+
fdcjazDIBLIxwJu5QwvTNW8lOLnJ46g4sf1WJoUdNTbR0BaC7HHj1inVWi0p7IuN
66EPGzJOSjLK+vW+J0ncPDEgLCV74RF/0nR5fVTdrmiopPrzFuguHf9S9gYI3Zun
Yl8FJUu4kRO6JPPTicUXWX+8XZmE94aK14RCJL23nOSi8T1eW8JLW43dCBRO8QUE
Aso1t2pypm/1zZexJdOV8yGME3g5l2W6PLgpz58DBECgqc/kda+VWgEAp7rO2A==
=EPL3
-----END PGP PUBLIC KEY BLOCK-----
EOF

[[ options[release] -ge DEFAULT_RELEASE ]] ||
. "legacy/${options[distro]}$(( --DEFAULT_RELEASE )).sh"
