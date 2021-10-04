# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=fedora [release]=31).

# Override buildroot creation to set the container image file name and URL.
eval "$(declare -f create_buildroot | $sed -e 's/cver=.*/cver=1.9/' \
    -e 's,dl.fedoraproject.org/pub,archives.fedoraproject.org/pub/archive,')"

# Override repository definitions to ignore disabled cisco stuff.
eval "$(declare -f create_buildroot distro_tweaks |
$sed 's/[^*]*cisco[^*]*/modular/')"

# Override ramdisk creation since the kernel is too old to support zstd.
eval "$(declare -f create_buildroot | $sed 's/ zstd//')"
eval "$(declare -f configure_initrd_generation | $sed /compress=/d)"
eval "$(declare -f relabel squash build_systemd_ramdisk | $sed \
    -e 's/zstd --[^|>]*/xz --check=crc32 -9e /')"

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import
        $gpg --verify "$1"
        [[ $($sha256sum "$2") == $($sed -n '/=/{s/.* //p;q;}' "$1")\ * ]]
} << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFxq3QMBEADUhGfCfP1ijiggBuVbR/pBDSWMC3TWbfC8pt7fhZkYrilzfWUM
fTsikPymSriScONXP6DNyZ5r7tgrIVdVrJvRIqIFRO0mufp9HyfWKDO//Ctyp7OQ
zYw6NVthO/aWpyFfJpj6s4iZsYGqf9gByV8brBB8v8jEsCtVOj1BU3bMbLkMsRI9
+WiLjDYyvopqNBQuIe8ogxSxpYdbUz6+jxzfvhRoBzWdjITd//Gjd90kkrBOMWkO
LTqO133OD1WMT08G5NuQ4KhjYsVvSbBpfdkTcNuP8gBP9LxCQDc+e1eAhZ95g3qk
XLeKEK9j+F+wuG/OrEAxBsscCxXRUB38QH6CFe3UxGoSMnBi+jEhicudo+ItpFOy
7rPaYyRh4Pmu4QHcC83bNjp8NI6zTHrBmVuPqkxMn07GMAQav9ezBXj6umqTX4cU
dsJUavJrJ3u7rT0lhBdiGrQ9zPbL07u2Kn+OXPAC3dKSf7G8TvwNAdry9esGSpi3
8aa1myQYVZvAlsIBkbN3fb1wvDJE5czVhzwQ77V2t66jxeg0o9/2OZVH3CozD2Zj
v28LHuW/jnQHtsQ0fUyQYRmHxNEVkW10GGM7fQwxzpxFFS1O/2XEnfMu7yBHZsgL
SojfUct0FhLhEN/g/IINX9ZCVrzK5/De27CNjYE1cgYD/lTmQ0SyjfKVwwARAQAB
tDFGZWRvcmEgKDMxKSA8ZmVkb3JhLTMxLXByaW1hcnlAZmVkb3JhcHJvamVjdC5v
cmc+iQI+BBMBAgAoAhsPBgsJCAcDAgYVCAIJCgsEFgIDAQIeAQIXgAUCXGrkTQUJ
Es8P/QAKCRBQyzkLPDNZxBmDD/90IFwAfFcQq5ENl7/o2CYQ9k2adTHbV5RoIOWC
/o9I5/btn1y8WDhPOUNmsgbUqRqz6srlVplg+LkpIj67PVLDBwpVbCJC8o1fztd2
MryVqdvu562WVhUorII+iW7nfqD0yv55nH9b/JR1qloUa8LpeKw84JgvxF5wVfyR
id1WjI0DBk2taFR4xCfU5Tb262fbdFj5iB9xskP7oNeS29+SfDjlnybtlFoqr9UA
nY1uvhBPkGmj45SJkpfP+L+kGYXVaUd29M/q/Pt46X1KDvr6Z0l8bSUEk3zfcNdj
uEhtHBqSy1UPPAikGX1Q5wGdu7R7+mv/ARqfI6OC44ipoOMNK1Aiu6+slbPYphwX
ighSz9yYuG0EdWt7akfKR0R04Kuej4LXLWcxTR4l8XDzThYgPP0g+z0XQJrAkVhi
SrzICeC3K1GPSiUtNAxSTL+qWWgwvQyAPNoPV/OYmY+wUxUnKCZpEWPkL79lh6CM
bJx/zlrOMzRumSzaOnKW9AOliviH4Rj89OmDifBEsQ0CewdHN9ly6g4ZFJJGYXJ5
HTb5jdButTC3tDfvH8Z7dtXKdC4iqJCIxj698Xn8UjVefZQ2nbv5eXcZLfHtvbNB
TTv1vvBV4G7aiHKYRSj7HmxhLBZC8Y/nmFAemOoOYDpR5eUmPmSbFayoLfRsFXmC
HLs7cw==
=6hRW
-----END PGP PUBLIC KEY BLOCK-----
EOF

# OPTIONAL (BUILDROOT)

function enable_repo_rpmfusion_free() {
        local key="RPM-GPG-KEY-rpmfusion-free-fedora-${options[release]}"
        local url="https://download1.rpmfusion.org/free/fedora/releases/${options[release]}/Everything/$DEFAULT_ARCH/os/Packages/r/rpmfusion-free-release-${options[release]}-1.noarch.rpm"
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script "$url"
} << 'EOF'
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFvEZi0BEADeq0E2/aYDWMYnUBloxAamr/DBo21/Xida69lQg/C8wGB/jz+i
J9ZDEnLRDGlotBl3lwOhbzwXxk+4azH77+JIuUDiPkBb6e7rld0EMWNykLuWifV0
Eq7qVBtr1cQfvLMDySvzIBPEGy3IbFnr7H7diR+A0WiwltVLcv4wW/ESRZUChBxy
TGgQrYk98TGiJGMWlwi7IzopOliAYrc7oM1XyZQlTffhS5b0ygiwIxGOOjVR3waB
m//0PVj8hZ+kHBgn2hXnLlWBkCRosxHmg+xcosUBgfBqKBPN8M800F6svvZS1msN
mef7y2QytA9LSpey6mznqKEY8x8+9Ub4FCGiEEw8SoDCU48NpmADr6PXoJAtihEi
4NuBiqzpabKDR7IfhEWNgVM840OCmizFyT9L++SDZmww8rUHx55VOzVEf4fSRPXY
gduexRo377+bj+wdpKfrUddkbdxuDVWweq8k5fZz7Y7HYtM60j9WxtUoLF37MNgZ
5bwrOU2NhLP+aqwyeE86/BqDdKVzxeq+PAaIl1ujTqbmJYJO0Kmt4G+GPhj6TpTq
+X+Ci+YskPEcp7dqpH38rpuA3ZAVH4tHkW9UFFBHrvnxuOLrrAflondgLTo1xNo6
E8Qrq7PGCjq/FdVM9tC3hupeKuXz5jaf65qbln4COromTXm5KyNOlWVgMwARAQAB
tFNSUE0gRnVzaW9uIGZyZWUgcmVwb3NpdG9yeSBmb3IgRmVkb3JhICgzMSkgPHJw
bWZ1c2lvbi1idWlsZHN5c0BsaXN0cy5ycG1mdXNpb24ub3JnPokCRQQTAQgALxYh
BFmn/gf2ZMGydofF0m3u8FHEgZN6BQJbxGYtAhsDBAsJCAcDFQgKAh4BAheAAAoJ
EG3u8FHEgZN6E5EQAN5kzvCyT/Ev6H/rS4QQE6+Zxb9YCGnlUOwPXcwtAqjGl4Hn
kt9LXnrd4DThLBLEGZUpBe5/oNuZOLWRWvTG7UHR+pBdtxIyqUlxBhiIwSe+Q7rZ
gehiXl2PhnaBHyTLoFGczNWiqKSIORnSmVg4SXuteG4So0PzRWBD9r2/7P/mZGyd
wyiH34YUzsedPOO1sER8o+tQ6C9RlRmhZRQ9hBJIymga1FfCms6X5lEFfbsuSjEt
acLvLJuO7bxfoYPiC2l+psFAitgT7UeEm/KW/Ul2M2YVONu1pRCkEoJzJ4B1ki9/
MK6Kw9QyQ6KXmOmzckJaInZQrwtcffjsdCjdQgoPUA//PVsysM4dtE7TPx2iRC2S
Vci0eGT+XV3tUlDDlMLfx6PhpfAddN3okGIWE0Nwc9yNwwn+R2H/Nrw0Q74qiwP7
uCgzGQBEKOATwJdm/EbtzSOzTgeunrlb1HO+XgjE+VBxp9vdzS/sOecixPyGdjW3
B1NIHAU1O9tgQcBNSJ4txKEnKHw92HViHLXpOVIIeXW+2bjtgTtTE3TfAYVnyLMn
uplg21hoH2L+fC281fgV64CzR+QjOiKWJSvub6wzy1a7/xPce8yaE89SwmxxVroS
Ia81vrdksRmtLwAhgJfh6YoSdxKWdtB+/hz2QwK+lHV368XzdeAuWQQGpX3T
=NNM4
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$1" > rpmfusion-free.rpm
curl -L "${1/-release-/-release-tainted-}" > rpmfusion-free-tainted.rpm
rpm --checksig rpmfusion-free{,-tainted}.rpm
rpm --install rpmfusion-free{,-tainted}.rpm
exec rm -f rpmfusion-free{,-tainted}.rpm
EOF

function enable_repo_rpmfusion_nonfree() {
        local key="RPM-GPG-KEY-rpmfusion-nonfree-fedora-${options[release]}"
        local url="https://download1.rpmfusion.org/nonfree/fedora/releases/${options[release]}/Everything/$DEFAULT_ARCH/os/Packages/r/rpmfusion-nonfree-release-${options[release]}-1.noarch.rpm"
        enable_repo_rpmfusion_free
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script "$url"
} << 'EOF'
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFvEZjsBEADo+8aA0e20azf2vU4JJ2rVHnr9RpVUcRYmr/rFEsEeYMIvDAYz
ssprKuuz89XTe5OR8RSrTIVFOTqYrZYxuQbR35rzr9wpk45szcUMDNzi0L83AemS
v1JgBF2gSoF9Ajbhbdwxxqje+yn86u0xWWsG4Xu1N/KZE/oyqAYwWzH9nizrSRSv
SCsjZMk4SwEPB0lp2zTf21k5YwIv05+ubHq5/h9WScjjoA4LCJHIikNptONFemhS
Ys3Vsacd0g4mAx3AyU8gGaFkQXapwhQWi1/UCbqFT/3S1ZApYthdYBpFwSv7PgUa
BBJGFzwxrch9NF1wHivO4uzmPK2V8REKt2EgwPUfaAYCabPxxFFsWNOimv1zz3Wb
2DPZfE1YDjAi4qNfXENkqSReys7ETi2fGw2pr6PQtLJFYLbpKwXVvdr0PuAPPNQo
kCAuCZKnNitxsxyaGYxN2gq3D6excKpo+3JQAdRTdC+vAFACs41QDLCLBYQUL4zn
eXR/hkSmyeEDyrkuRztqUxI0eobMOS6KI6c2u+tYhWQY1OH1piV1aOa4OQQKFdZH
6WQAnbMqafG4lPmEO5cDT4JNRzWfyZXXa750mq6X3r2iRZMlroHoJAMUmF6+r8vP
AfjC3Haqfbp6HlNpTET8GU8eeeNQM33Qpq1H2tGJPIt3ZVHOTzjjMnvFdwARAQAB
tFZSUE0gRnVzaW9uIG5vbmZyZWUgcmVwb3NpdG9yeSBmb3IgRmVkb3JhICgzMSkg
PHJwbWZ1c2lvbi1idWlsZHN5c0BsaXN0cy5ycG1mdXNpb24ub3JnPokCRQQTAQgA
LxYhBEyrlRp0k9ksrewEIZzmOgNUqGCSBQJbxGY7AhsDBAsJCAcDFQgKAh4BAheA
AAoJEJzmOgNUqGCSkzwP/35oDsqFQNZGT2PJ3BpLkK/e8INCRsBgUHHzQiGri69v
OBDt6RoJwKEYfsx7ps0oRhci6NZ5aTJL4g25xBibWB9dvce4c25Kho7VHassxXzv
j6MrAuFNFHWpNNGXgiBTfMBOqcLxfx550wJyzyUVxxsmjbRm8Irz/ijZXavzyTw5
xNmZw6a2XH1Zx9bNdv+o5I5pkmdJJGSw6BbI7j5xysV+A5yIFtCnKCwhsXrGRjnR
9V8MuocAXjzayLWJ4E0daZkJlyR5mhYuae4PR1wt75qj8UesjWTAniQFlWMe52+G
Iqukb6TvxrLLTdaFi8orpoDG5PsdQ2kfyRQDcK5UMM4X8BC59Bq0NtuIezMio40O
1wGZFf1tUdGCImf5JtboKRTeAp32uvPjYR1Bbya8Yup6OuCrKDrdOdqKlULFp3H+
ia8W8hFCaGgvnpNveoBLFcMq6xxorQ4LhEcwnLABs9Y8UnL5Ao2ozijVA7Pkhdep
dt5CYmEq77bxpQT1tLUt9jp246gZgMQQDZAR6BW+fg3FCpXDWguxF+Xzuf7JuL9O
V2SKYTbdiljladNZO0sq566U6GJptKhl8pHlihkNyHc6jkQGxnzpzFolTUl66jbc
f9jO+f+R9C+FDT1fcPPIolYTBRCvYQ9B6c+olHVTNNYUmW36TThsbXiYeqQw4JPA
=Wn2x
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$1" > rpmfusion-nonfree.rpm
curl -L "${1/-release-/-release-tainted-}" > rpmfusion-nonfree-tainted.rpm
rpm --checksig rpmfusion-nonfree{,-tainted}.rpm
rpm --install rpmfusion-nonfree{,-tainted}.rpm
exec rm -f rpmfusion-nonfree{,-tainted}.rpm
EOF

[[ options[release] -ge DEFAULT_RELEASE ]] ||
. "legacy/fedora$(( --DEFAULT_RELEASE )).sh"
