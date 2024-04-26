# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=fedora [release]=39).

# Override buildroot creation to use the pre-OCI container format.
eval "$(declare -f create_buildroot | $sed 's/cver=.*/cver=1.5/
/image=/{s/-Generic..DEFAULT_ARCH-/-/;s/oci/$DEFAULT_ARCH/;}
/mkdir.*oci/,/tar.*layer/c\
        $tar -xJOf "$output/image.txz" "*/layer.tar" | $tar -C "$buildroot" -x\
        $rm -f "$output/checksum" "$output/image.txz"')"

# Override package installation to set the previous authentication profile.
eval "$(declare -f install_packages | $sed 's/select local/select minimal/')"

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import
        $gpg --verify "$1"
        [[ $($sha256sum "$2") == $($sed -n '/=/{s/.* //p;q;}' "$1")\ * ]]
} << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGLykg8BEADURjKtgQpQNoluifXia+U3FuqGCTQ1w7iTqx1UvNhLX6tb9Qjy
l/vjl1iXxucrd2JBnrT/21BdtaABhu2hPy7bpcGEkG8MDinAMZBzcyzHcS/JiGHZ
d/YmMWQUgbDlApbxFSGWiXMgT0Js5QdcywHI5oiCmV0lkZ+khZ4PkVWmk6uZgYWf
JOG5wp5TDPnoYXlA4CLb6hu2691aDm9b99XYqEjhbeIzS9bFQrdrQzRMKyzLr8NW
s8Pq2tgyzu8txlWdBXJyAMKldTPstqtygLL9UUdo7CIQQzWqeDbAnv+WdOmiI/hR
etbbwNV+thkLJz0WD90C2L3JEeUJX5Qa4oPvfNLDeCKmJFEFUTCEdm0AYoQDjLJQ
3d3q9M09thXO/jYM0cSnJDclssLNsNWfjJAerLadLwNnYRuralw7f74QSLYdJAJU
SFShBlctWKnlhQ7ehockqtgXtWckkqPZZjGiMXwHde9b9Yyi+VqtUQWxSWny+9g9
6tcoa3AdnmpqSTHQxYajD0EGXJ0z0NXfqxkI0lo8UxzypEBy4sARZ4XhTU73Zwk0
LGhEUHlfyxXgRs6RRvM2UIoo+gou2M9rn/RWkhuHJNSfgrM0BmIBCjhjwGiS33Qh
ysLDWJMdch8lsu1fTmLEFQrOB93oieOJQ0Ysi5gQY8TOT+oZvVi9pSMJuwARAQAB
tDFGZWRvcmEgKDM5KSA8ZmVkb3JhLTM5LXByaW1hcnlAZmVkb3JhcHJvamVjdC5v
cmc+iQJOBBMBCAA4FiEE6PI5lvIyGGQMtEy+dc9axBi450wFAmLykg8CGw8FCwkI
BwIGFQoJCAsCBBYCAwECHgECF4AACgkQdc9axBi450yd4w//ZtghbZX5KFstOdBS
rcbBfCK9zmRvzeejzGl6lPKfqwx7OOHYxFlRa9MYLl8QG7Aq6yRRWzzEHiSb0wJw
WXz5tbkAmV/fpS4wnb3FDArD44u317UAnaU+UlhgK1g62lwI2dGpvTSvohMBMeBY
B5aBd+sLi3UtiSRM2XhxvxaWwr/oFLjKDukgrPQzeV3F/XdxGhSz/GZUVFVprcrB
h/dIo4k0Za7YVRhlVM0coOIcKbcjxAK9CCZ8+jtdIh3/BN5zJ0RFMgqSsrWYWeft
BI3KWLbyMfRwEtp7xSi17WXbRfsSoqwIVgP+RCSaAdVuiYs/GCRsT3ydYcDvutuJ
YZoE53yczemM/1HZZFI04zI7KBsKm9NFH0o4K2nBWuowBm59iFvWHFpX6em54cq4
45NwY01FkSQUqntfqCWFSowwFHAZM4gblOikq2B5zHoIntCiJlPGuaJiVSw9ZpEc
+IEQfmXJjKGSkMbU9tmNfLR9skVQJizMTtoUQ12DWC+14anxnnR2hxnhUDAabV6y
J5dGeb/ArmxQj3IMrajdNwjuk9GMeMSSS2EMY8ryOuYwRbFhBOLhGAnmM5OOSUxv
A4ipWraXDW0bK/wXI7yHMkc6WYrdV3SIXEqJBTp7npimv3JC+exWEbTLcgvV70FP
X55M9nDtzUSayJuEcfFP2c9KQCE=
=J4qZ
-----END PGP PUBLIC KEY BLOCK-----
EOF

[[ options[release] -ge DEFAULT_RELEASE ]] ||
. "legacy/${options[distro]}$(( --DEFAULT_RELEASE )).sh"
