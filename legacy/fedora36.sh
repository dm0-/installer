# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=fedora [release]=36).

# Override buildroot creation to set the container image file name.
eval "$(declare -f create_buildroot | $sed 's/cver=.*/cver=1.5/')"

# Override buildroot post-install to fix AMD microcode in broken versions.
eval "$(declare -f create_buildroot | $sed 's/amd-ucode-firmware/linux-firmware/g')"
[[ options[release] -gt 33 ]] && eval "$(declare -f create_buildroot | $sed '
/script.*EOF/,/EOF$/s,^exec \(.*\),\1\nfor fw in /lib/firmware/amd-ucode/*.bin.xz ; do unxz "$fw" ; done,')"

# Point EOL releases at the archive repository server.
eval "$(declare -f enable_repo_rpmfusion_{,non}free | $sed '
s,download1.rpmfusion.org/\([^/]*\),rhlx01.hs-esslingen.de/Mirrors/archive.rpmfusion.org/\1-archive,g')"

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import
        $gpg --verify "$1"
        [[ $($sha256sum "$2") == $($sed -n '/=/{s/.* //p;q;}' "$1")\ * ]]
} << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGAkKwgBEAC+IQKqp/BI1VIvRRqcnRoAxkzsY3pxIS1L+C4gaWjIMf1eBBTq
v9eKd4xHsW80VL/tl81WZWO/7JXKmgHODiXrv4HmDIOo6Z1hxehjVRF3Ih4+sKHR
XCJgwcdJnMfqTKnHiycQggeDuheWbfjV2Fgmvxy0jh0M5PCB5taNz41LmPOaUQmn
PXcI05CjP5msKjRBObw5Cd2oad60pTNhnBWRf288S8W4wH4jNISOZLZTOf6HU5gJ
w9wU9RZoaz8kZPNArlJjZsN83S0XLCxpa6UUgYdzPDHOWGtcWGs3bvNAlTYuacun
oICOvTH/ZJU7mgaZbbdSPVLDJdLBKRVgHbdTAK0J913FEiU93GJR5bf/W5FMN7DV
6hsJVMiY/knJmkTFE9whDSjEc0TAYhQuC1HnzvMPGJvkeEz9nRqna5QUuo7V6LI4
fZNTSlqFyIi/Oa3ZoliOyOshxJmU3y1HaNcHerO1nFbTtZ7s/TKBhY9oFq4T4gJV
yFWy33p/JDxOtlVjpHEkzwXGdPe6R4xK8xHObEVraOMZMaweII+tMOGwVbxZu2kC
A1aflM+oeyU1Fx9qqM0+dYyHO+kp3M5UtfM006RcNcdfoGrA4l6z9sUnHKsYzOLP
RvKkzxiX3T91vHtRGCXjPOgOsJJzjkFtE1a5oFZg39fC99HZdbX0rUqAtQARAQAB
tDFGZWRvcmEgKDM2KSA8ZmVkb3JhLTM2LXByaW1hcnlAZmVkb3JhcHJvamVjdC5v
cmc+iQJOBBMBCAA4FiEEU97Sy5Iti42eY/0YmZ98vzircfQFAmAkKwgCGw8FCwkI
BwIGFQoJCAsCBBYCAwECHgECF4AACgkQmZ98vzircfSGaxAAlDBWuY1Ch3YsssGE
uaeOuaHmDj08p08WUAFUPBN0ID+0pmRQjywFzrufw8Z2g/lHwic+tpXXr/RtMmcl
+WzLh1E34TRqEngjDJ27QBq1Jyid3h1manKLhZhJ8b1usKHP7Dqh7n+eMTv2Qgrt
6MrCNe4otWZ9WJ5vp/Bay5yAtU6lNoWBmJ+6BS1/2mg2jhoXrfg/Vey+/i6nYZIk
M4IcYCyGCi9rjc8NMgkCyzPkPJtsy2taB+VdUcZyjFpc1acmC8sR/2/SEl4+pOtM
UzW+OUOQFrerX/8MC5LqvmtsiPMyRDCOw3reJTXyoUIehoHoK9QtAdIRRP2nAkPy
GKycVzsLbtheJXUZharXL1DwOkpMNlm3hp9BxX89m7dLblMSjtrQPs8CkpAExAQW
FBltsD73ZhGnfE/XdWp7343m1w5W2m85/rczP+2et+c+HPmYTgaJTu8fAF0FoTDd
uD1r9DxRa2oN3YBiPP/nXnhJaH//GgF/RRw7Fbc66fCh8DTrMsPgmyi/O3/pdSGe
k0UqEfSdzNPbl7gVFlCbr4Ur5n1ph+sEZqOhMuyszLZZvYvUrHsDuanML5X25coP
h+rqyjHJJeYlS2tMAQB1fmHB0LWhRhKYaOROAXFmUutFUxVVoigNCl8mV561DCz6
6/zy81ZGeyUGOEIZ1NFuoY0EhC8=
=KaIq
-----END PGP PUBLIC KEY BLOCK-----
EOF

[[ options[release] -ge DEFAULT_RELEASE ]] ||
. "legacy/${options[distro]}$(( --DEFAULT_RELEASE )).sh"
