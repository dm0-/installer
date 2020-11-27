declare -f verify_distro &> /dev/null  # Use ([distro]=fedora [release]=30).

options[verity_sig]=

# Override buildroot creation to set the container image file name.
eval "$(declare -f create_buildroot | $sed 's/cver=.*/cver=1.2/')"

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFturGcBEACv0xBo91V2n0uEC2vh69ywCiSyvUgN/AQH8EZpCVtM7NyjKgKm
bbY4G3R0M3ir1xXmvUDvK0493/qOiFrjkplvzXFTGpPTi0ypqGgxc5d0ohRA1M75
L+0AIlXoOgHQ358/c4uO8X0JAA1NYxCkAW1KSJgFJ3RjukrfqSHWthS1d4o8fhHy
KJKEnirE5hHqB50dafXrBfgZdaOs3C6ppRIePFe2o4vUEapMTCHFw0woQR8Ah4/R
n7Z9G9Ln+0Cinmy0nbIDiZJ+pgLAXCOWBfDUzcOjDGKvcpoZharA07c0q1/5ojzO
4F0Fh4g/BUmtrASwHfcIbjHyCSr1j/3Iz883iy07gJY5Yhiuaqmp0o0f9fgHkG53
2xCU1owmACqaIBNQMukvXRDtB2GJMuKa/asTZDP6R5re+iXs7+s9ohcRRAKGyAyc
YKIQKcaA+6M8T7/G+TPHZX6HJWqJJiYB+EC2ERblpvq9TPlLguEWcmvjbVc31nyq
SDoO3ncFWKFmVsbQPTbP+pKUmlLfJwtb5XqxNR5GEXSwVv4I7IqBmJz1MmRafnBZ
g0FJUtH668GnldO20XbnSVBr820F5SISMXVwCXDXEvGwwiB8Lt8PvqzXnGIFDAu3
DlQI5sxSqpPVWSyw08ppKT2Tpmy8adiBotLfaCFl2VTHwOae48X2dMPBvQARAQAB
tDFGZWRvcmEgKDMwKSA8ZmVkb3JhLTMwLXByaW1hcnlAZmVkb3JhcHJvamVjdC5v
cmc+iQI4BBMBAgAiBQJbbqxnAhsPBgsJCAcDAgYVCAIJCgsEFgIDAQIeAQIXgAAK
CRDvPBEfz8ZZudTnD/9170LL3nyTVUCFmBjT9wZ4gYnpwtKVPa/pKnxbbS+Bmmac
g9TrT9pZbqOHrNJLiZ3Zx1Hp+8uxr3Lo6kbYwImLhkOEDrf4aP17HfQ6VYFbQZI8
f79OFxWJ7si9+3gfzeh9UYFEqOQfzIjLWFyfnas0OnV/P+RMQ1Zr+vPRqO7AR2va
N9wg+Xl7157dhXPCGYnGMNSoxCbpRs0JNlzvJMuAea5nTTznRaJZtK/xKsqLn51D
K07k9MHVFXakOH8QtMCUglbwfTfIpO5YRq5imxlWbqsYWVQy1WGJFyW6hWC0+RcJ
Ox5zGtOfi4/dN+xJ+ibnbyvy/il7Qm+vyFhCYqIPyS5m2UVJUuao3eApE38k78/o
8aQOTnFQZ+U1Sw+6woFTxjqRQBXlQm2+7Bt3bqGATg4sXXWPbmwdL87Ic+mxn/ml
SMfQux/5k6iAu1kQhwkO2YJn9eII6HIPkW+2m5N1JsUyJQe4cbtZE5Yh3TRA0dm7
+zoBRfCXkOW4krchbgww/ptVmzMMP7GINJdROrJnsGl5FVeid9qHzV7aZycWSma7
CxBYB1J8HCbty5NjtD6XMYRrMLxXugvX6Q4NPPH+2NKjzX4SIDejS6JjgrP3KA3O
pMuo7ZHMfveBngv8yP+ZD/1sS6l+dfExvdaJdOdgFCnp4p3gPbw5+Lv70HrMjA==
=BfZ/
-----END PGP PUBLIC KEY BLOCK-----
EOF
        $gpg --verify "$1"
        test x$($sed -n '/=/{s/.* //p;q;}' "$1") = x$($sha256sum "$2" | $sed -n '1s/ .*//p')
}

# OPTIONAL (BUILDROOT)

function enable_rpmfusion() {
        local key="RPM-GPG-KEY-rpmfusion-free-fedora-${options[release]}"
        local url="https://download1.rpmfusion.org/free/fedora/releases/${options[release]}/Everything/$DEFAULT_ARCH/os/Packages/r/rpmfusion-free-release-${options[release]}-1.noarch.rpm"
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script << EOF
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFrUUycBEADfDoQDUWJBi2QpXmFf7be+DMqBjgSZp3ibe29ON1iLe+gfyFjC
0KCuuz+RdfRizKkovlqMC7ucWqDIkc3fCsoWpb+Hpfw51WvLQCyodB0suHfaY0Rk
k8Jhg5u0qnL8lJfiFEiVesKoUziIf+phLKpITK2LBD0kBNn5OnkWrPwNuN0wyvXP
HAqxz3KZxxwBEn1RwUhYIJCZStaFoTDziWHIB2cYIKSdfquOh1UCVuQj63WnUXNL
e4Wqbc62xJQBZkCfs3+r4FybcGrB07Mju0i7MeWzH6dMHYx6ZkGyA5CmOYfoRV2o
CfOHqm3e+MvHDN+7JF6epNSQyMX47KIA5foJZlMe0RhuO8SwHCMc6d/Zc7iFKmG1
IsWdBzGvJkMv1g4OaEAYRuVO5jWWO4370UVqQ9kvzky3aqGI391wekSSqDbLer6a
8isf4QDEqjzhVswxXg99I4zkXlMcYkBRumGBtq1KkcAtLoobVEg1WbQbQQTu4j/H
ZKgFadwhasJK1jN+PtW+erV0l1KyDzjR4vTRR9AWg9ahsTLtRe9HvkBLBhKtrhW0
oPqOW5I3n0LChnegYy7jit5ZPGS7oZvzbu+zok+lwQFLZdPxM2VuY6DQE8BNdXEP
3nLNGbVubv/MZILOws8/ACiONeW9C+RvzYznwmM+JqqhqmKiyr8WWlBfAQARAQAB
tFNSUE0gRnVzaW9uIGZyZWUgcmVwb3NpdG9yeSBmb3IgRmVkb3JhICgzMCkgPHJw
bWZ1c2lvbi1idWlsZHN5c0BsaXN0cy5ycG1mdXNpb24ub3JnPokCRQQTAQgALxYh
BIDDssbnJ/PgkrRz4D3yzkPArtpuBQJa1FMnAhsDBAsJCAcDFQgKAh4BAheAAAoJ
ED3yzkPArtpusgsP/RmuZOKEgrGL12uWo9OEyZLTjjJ9chJRPDNXPQe7/atNJmWe
WwkWbKcWwSivwGP04SsJF1iWRcSwCOLe5wBSpuM5E1XsDufzKsLH1WkjOtDQ+O8U
kkJwV64WT06FkSUze+cS7ni5LSObVqPvBtbKFl8lWciG1IDlK5++XW2VLD3dghAW
5boFZjoVNZoYhlyeZmtcDVlFdXex5Sw0B/gJY4uaHXBXrA1YyE4vBlrSDYrfh4eU
glSGNMNS++78bQsN/C3VmtXpWsvNJa4jxYaXFOJd5g3iX5ttDQYF46PgJckZVurA
8PT066i4eJOwqDPnOQncsudcpbLPt+0F3cyeDPtjKh+RY48hAhTW0/lDq2onhGPk
SOTDhPrx6vWLqDNBKOio3VloFdEOCsm2OniGZojJADm6m6kErY6n3On3y9TE2GDm
Bx8apPxN7FJvwFqvieZt6B1R+57VStQ0YBCsfC1i5EVsNPnyoNqwvxs2IGsn3P/+
SuCw9+qa5aRsF+jdnHxKMmj1xm8dVtCCLfaMb4cl7wxgq9zolvlbRFnfHfhRoKhp
fs3khghy5i2AU/bOChxRngX2QWR1A117IeADWtuspMFEOyeU5BlMcqjkFdOZI3jX
0VmGnXLcUEIa89z/0ktU6TW3MLQ/laFqj5LhGR9jzaDL6S7pOzNqQT4p3jzJ
=S0gf
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$url" > rpmfusion-free.rpm
curl -L "${url/-release-/-release-tainted-}" > rpmfusion-free-tainted.rpm
rpm --checksig rpmfusion-free{,-tainted}.rpm
rpm --install rpmfusion-free{,-tainted}.rpm
exec rm -f rpmfusion-free{,-tainted}.rpm
EOF
        test "x$*" = x+nonfree || return 0
        key=${key//free/nonfree}
        url=${url//free/nonfree}
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script << EOF
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFrUUy4BEAC0TX9UViv0ZWUMruCuR3s8niI388HlqPBF4eKv30V+zlwFiw/6
JfrWlOZ1QfcK5DJbQT3LMVsVyGU3KTCquHGTPusSPFVpG1KLhBwXGMdZ3/y14xGZ
xI37PyaZ5T170NchcST14f7cjkLtBuJ3IOIMwv1Uxi5Oc8QOo/i3RHMiiE1JKGuA
FR8Td77VioV9+gr41VlexdjeAvf0UGylstbLkiEqYig2xhbD49vGZ97V/PJXEbpd
nb6nJz0SUIKczQYbln7Arm9/8H91dBgWFkp8URVxtdQn/GJ3D6DBs+t6PlS1QD5m
2k999hDy0iRduwc4t2mO5jUio7LeMi0zkCtvx4HzJXSYissx7uR3odi32N5Z3Ywd
ZnmdqCDVXx7QXSQ0V6UIffPHB+JzFT4EfIENCp55puzMXJZkugaP8PX3VtbPsCz6
WMddNs7674VrJR7uhtmpumfNo9taXJdesZbcuUs6DyoW24WBEVDjlhPDjKCID0bm
0uPWheyxt3I4kTcTaRWJfQN8rQYHFtRpIE9qCDRNCsdYoMjuGHIlcBPTcNn3ksfv
Hwrr7rYpKPHp/lkhoneWXhnBWNd6r5/1zy7bHxiSPgbPZt2YB5jAE3jHRmVyHCQo
J6/+OcRhbL2cKUOBvuwQQXe/7qPPSjnkCamiQoiSZGOL39f8ql/rKJg98wARAQAB
tFZSUE0gRnVzaW9uIG5vbmZyZWUgcmVwb3NpdG9yeSBmb3IgRmVkb3JhICgzMCkg
PHJwbWZ1c2lvbi1idWlsZHN5c0BsaXN0cy5ycG1mdXNpb24ub3JnPokCRQQTAQgA
LxYhBIAXHI0syKq4TIRI6b3W7MQdFKeVBQJa1FMuAhsDBAsJCAcDFQgKAh4BAheA
AAoJEL3W7MQdFKeVjK8QAIjV7blJJbCShlCpU1ul5wcDYMuF6nw+DmaPuL1koAYF
dYRP+o9Sho/7tjkLT6lQaePSPF/SBxUjgI3+0HLb3soTwwSMfkCxF3DXlO9hUjJr
L1jIUubx2RpBhjWpwpdJ/2JZHb2fwlKnKfS0bjyypV6QOngbspyXi/FKyGYF1UQO
WZG0fuOr/vu1+VUY2YN8qnCkuyCnpTy5VbfWOht98nfnCf3vo+FXoMWx7wKB+CoY
M9FryDlyF5te/z5dsv7/8MiSavw5vpdDdzqaiN7j69m4nHYRYco9pj3oM2WN/iu8
4Quf2Zfa4YgdXO1oYn7GYCmJZftnvEBWVZ1DjgGvoa1FV/suvDlc6+x0g6M2bORX
jlnG1cjDD8eKjhy2HvVQLbnJxGce4wwvCHppgs6lHowIMNfgPvKFi1Lt2ABw0ojR
wjYELGwF60s2u0Doh0Um3SNsFWGF4jcSyq/5+fdk93qPqEGv44tjrbRtC3O5KNCZ
YTLbiR0ZcubpQap7pZHJLSbjPh74HrsgXtNNpnDNCQOQecSIuiff5fZzN7tyJrLL
NCfJC5FlD/HHbNLLBYBOCM6N7h3gcyAJBGp6JwpchbZf5kOFMWlZIr8J8TDv2EHC
shobGp/ukk6OFzG9MOnPFn19tnO1ZMB+ewATd968K+3yEwJ2woX02iguq77LGPj4
=Gzco
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$url" > rpmfusion-nonfree.rpm
curl -L "${url/-release-/-release-tainted-}" > rpmfusion-nonfree-tainted.rpm
rpm --checksig rpmfusion-nonfree{,-tainted}.rpm
rpm --install rpmfusion-nonfree{,-tainted}.rpm
exec rm -f rpmfusion-nonfree{,-tainted}.rpm
EOF
}

[[ ${options[release]} -ge $DEFAULT_RELEASE ]]
