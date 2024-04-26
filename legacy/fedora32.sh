# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=fedora [release]=32).

# Override buildroot creation to set the container image file name.
eval "$(declare -f create_buildroot | $sed 's/cver=.*/cver=1.6/')"

# Override the networkd provider for when it was bundled with systemd.
eval "$(declare -f install_packages | $sed s/-networkd//)"

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import
        $gpg --verify "$1"
        [[ $($sha256sum "$2") == $($sed -n '/=/{s/.* //p;q;}' "$1")\ * ]]
} << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBF1RVqsBEADWMBqYv/G1r4PwyiPQCfg5fXFGXV1FCZ32qMi9gLUTv1CX7rYy
H4Inj93oic+lt1kQ0kQCkINOwQczOkm6XDkEekmMrHknJpFLwrTK4AS28bYF2RjL
M+QJ/dGXDMPYsP0tkLvoxaHr9WTRq89A+AmONcUAQIMJg3JxXAAafBi2UszUUEPI
U35MyufFt2ePd1k/6hVAO8S2VT72TxXSY7Ha4X2J0pGzbqQ6Dq3AVzogsnoIi09A
7fYutYZPVVAEGRUqavl0th8LyuZShASZ38CdAHBMvWV4bVZghd/wDV5ev3LXUE0o
itLAqNSeiDJ3grKWN6v0qdU0l3Ya60sugABd3xaE+ROe8kDCy3WmAaO51Q880ZA2
iXOTJFObqkBTP9j9+ZeQ+KNE8SBoiH1EybKtBU8HmygZvu8ZC1TKUyL5gwGUJt8v
ergy5Bw3Q7av520sNGD3cIWr4fBAVYwdBoZT8RcsnU1PP67NmOGFcwSFJ/LpiOMC
pZ1IBvjOC7KyKEZY2/63kjW73mB7OHOd18BHtGVkA3QAdVlcSule/z68VOAy6bih
E6mdxP28D4INsts8w6yr4G+3aEIN8u0qRQq66Ri5mOXTyle+ONudtfGg3U9lgicg
z6oVk17RT0jV9uL6K41sGZ1sH/6yTXQKagdAYr3w1ix2L46JgzC+/+6SSwARAQAB
tDFGZWRvcmEgKDMyKSA8ZmVkb3JhLTMyLXByaW1hcnlAZmVkb3JhcHJvamVjdC5v
cmc+iQI4BBMBAgAiBQJdUVarAhsPBgsJCAcDAgYVCAIJCgsEFgIDAQIeAQIXgAAK
CRBsEwJtEslE0LdAD/wKdAMtfzr7O2y06/sOPnrb3D39Y2DXbB8y0iEmRdBL29Bq
5btxwmAka7JZRJVFxPsOVqZ6KARjS0/oCBmJc0jCRANFCtM4UjVHTSsxrJfuPkel
vrlNE9tcR6OCRpuj/PZgUa39iifF/FTUfDgh4Q91xiQoLqfBxOJzravQHoK9VzrM
NTOu6J6l4zeGzY/ocj6DpT+5fdUO/3HgGFNiNYPC6GVzeiA3AAVR0sCyGENuqqdg
wUxV3BIht05M5Wcdvxg1U9x5I3yjkLQw+idvX4pevTiCh9/0u+4g80cT/21Cxsdx
7+DVHaewXbF87QQIcOAing0S5QE67r2uPVxmWy/56TKUqDoyP8SNsV62lT2jutsj
LevNxUky011g5w3bc61UeaeKrrurFdRs+RwBVkXmtqm/i6g0ZTWZyWGO6gJd+HWA
qY1NYiq4+cMvNLatmA2sOoCsRNmE9q6jM/ESVgaH8hSp8GcLuzt9/r4PZZGl5CvU
eldOiD221u8rzuHmLs4dsgwJJ9pgLT0cUAsOpbMPI0JpGIPQ2SG6yK7LmO6HFOxb
Akz7IGUt0gy1MzPTyBvnB+WgD1I+IQXXsJbhP5+d+d3mOnqsd6oDM/grKBzrhoUe
oNadc9uzjqKlOrmrdIR3Bz38SSiWlde5fu6xPqJdmGZRNjXtcyJlbSPVDIloxw==
=QWRO
-----END PGP PUBLIC KEY BLOCK-----
EOF

# OPTIONAL (BUILDROOT)

function enable_repo_rpmfusion_free() {
        local key="RPM-GPG-KEY-rpmfusion-free-fedora-${options[release]}"
        local url="https://rhlx01.hs-esslingen.de/Mirrors/archive.rpmfusion.org/free-archive/fedora/releases/${options[release]}/Everything/$DEFAULT_ARCH/os/Packages/r/rpmfusion-free-release-${options[release]}-1.noarch.rpm"
        [[ -s $buildroot/etc/pki/rpm-gpg/$key ]] || script "$url"
} << 'EOF'
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFyps4IBEADNQys3kVRoIzE+tbfUSjneQWYYDuONJP3i9tuJjKC6NJJCDBxB
NqxRdZm2XQjF4NThJHB+wOY6/M7XRzUVPE1LtoEaA/FXj12jogt7TN5aDT4VDyRV
nBKlsW4tW/FcxPS9R7lCLsnTfX16yr59vwA6KpLR3FsbDUJyFLRX33GMxZVtVAv4
181AeBA2WdTlebR8Cb0o0QowDyWkXRP97iV+qSiwhlOmCjl5LpQY1UZZ37VhoY+Y
1TkFT8fnYKe5FO8Q5b6hFcaIESvGQ0rOAQC1GoHksG19BoQm80TzkHpFXdPmhvJT
+Q3J1xFID7WVwMtturtoTzW+MPcXcbeOquz5PbEAB3LocdYASkDcCpdLxNsVIWbe
wVyXwTM8+/3kX+Pknc4PWdauOiap9w6og6x0ki1cVbYFo6X4mtfv5leIPkhfWqGn
ZRwLNzCr/ilRuqerdkwvf0G/GebnzoSc9Sqsd552CHuXbB51OK0zP3ZnkG3y8i0R
ls3J4PZY8IHxa1T4NQ4n0h4VrZ3TJhWQMvl1eI3aeTG4yM98jm3n+TQi73Z+PxjK
+8iAa1jTjAPew1qzJxStJXy6LfNyqwtaSOYI/MWCD9F4PDvxmXhLQu/UU7F2JPJ2
4VApuAeMUDnb2aSNyCb894sJG126BwfHHjMKGAJadJInBMg9swlrx/R+AQARAQAB
tFNSUE0gRnVzaW9uIGZyZWUgcmVwb3NpdG9yeSBmb3IgRmVkb3JhICgzMikgPHJw
bWZ1c2lvbi1idWlsZHN5c0BsaXN0cy5ycG1mdXNpb24ub3JnPokCRQQTAQgALxYh
BHvamO9ZMFCjSxaXq6DunYMQC82SBQJcqbOCAhsDBAsJCAcDFQgKAh4BAheAAAoJ
EKDunYMQC82SfX0QAJJKGRFKuLX3tPHoUWutb85mXiClC1b8sLXnAGf3yZEXMZMi
yIg6HEFfjpEYGLjjZDXR7vF2NzXpdzNV9+WNt8oafpdmeFRKAl2NFED7wZXsS/Bg
KlxysH07GFEEcJ0hmeNP9fYLUZd/bpmRI/opKArKACmiJjKZGRVh7PoXJqUbeJIS
fSnSxesCQzf5BbF//tdvmjgGinowuu6e5cB3fkrJBgw1HlZmkh88IHED3Ww/49ll
dsI/e4tQZK0BydlqCWxguM/soIbfA0y/kpMb3aMRkN0pTKi7TcJcb9WWv/X96wSb
hq1LyLzh7UYDULEnC8o/Lygc8DQ9WG+NoNI7cMvXeax80qNlPS2xuCwVddXK7EBk
TgHpfG4b6/la5vH4Un3UuD03q+dq2iQn7FSFJ8iaBODg5JJQOqBLkg2dlPPv8hZK
nb3Mf7Zu0rhyBm5DSfGkSGYv8JgRGsobek+pdP7bV2RPEmEuJycz7vV6kdS1BUvW
f3wwFYe7MGXD9ITUcCq3a2TabsesqwqNzHizUbNWprrg8nQQRuEupas2+BDyGIL6
34hsfZcS8e/N7Eis+lEBEKMo7Fn36VZZXHHe7bkKPpIsxvHjNmFgvdQVAOJRR+iQ
SvzIApckQfmMKIzPJ4Mju9RmjWOQKA/PFc1RynIhemRfYCfVvCuMVSHxsqsF
=hrxJ
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$1" > rpmfusion-free.rpm
curl -L "${1/-release-/-release-tainted-}" > rpmfusion-free-tainted.rpm
rpm --checksig --define=_pkgverify_{'flags 0x0','level all'} rpmfusion-free{,-tainted}.rpm
rpm --install rpmfusion-free{,-tainted}.rpm
exec rm -f rpmfusion-free{,-tainted}.rpm
EOF

function enable_repo_rpmfusion_nonfree() {
        local key="RPM-GPG-KEY-rpmfusion-nonfree-fedora-${options[release]}"
        local url="https://rhlx01.hs-esslingen.de/Mirrors/archive.rpmfusion.org/nonfree-archive/fedora/releases/${options[release]}/Everything/$DEFAULT_ARCH/os/Packages/r/rpmfusion-nonfree-release-${options[release]}-1.noarch.rpm"
        enable_repo_rpmfusion_free
        [[ -s $buildroot/etc/pki/rpm-gpg/$key ]] || script "$url"
} << 'EOF'
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFyptB8BEAC2C18FrMlCbotDF+Ki/b1sq+ACh9gl9OziTYCQveo4H/KU6PPV
9fIDlMuFLlWqIiP32m224etYafTARp3NZdeQGBwe1Cgod+HZ/Q5/lySJirsaPUMC
WQDGT9zd8BadcprbKpbS4NPg0ZDMi26OfnaJRD7ONmXZBsBJpbqsSJL/mD5v4Rfo
XmYSBzXNH2ScfRGbzVam5LPgIf7sOqPdVGUM2ZkdJ2Y2p6MHLhJko8LzVr3jhJiH
9AL0Z7f3xyepA9c8qcUx2IecZAOBIw18s9hyaXPXD4XejNP7WNAmClRhijhxBcML
TpDglKGe5zoxpXwPsavQxa7uUYVUHc83sfP04Gjj50CZpMpR9kfp/uLvzYf1KQRj
jM41900ZewXAAOScTp9vouqn23R8B8rLeQfL+HL1y47dC7dA4gvOEoAysznTed2e
fl6uu4XG9VuK1pEPolXp07nbZ1jxEm4vbWJXCuB6WDJEeRw8AsCsRPfzFk/oUWVn
kvzD0Xii6wht1fv+cmgq7ddDNuvNJ4aGi5zAmMOC9GPracWPygV+u6w/o7b8N8tI
LcHKOjOBh2orowUZJf7jF+awHjzVCFFT+fcCzDwh3df+2fLVGVL+MdTWdCif9ovT
t/SGtUK7hrOLWrDTsi1NFkvWLc8W8BGXsCTr/Qt4OHzP1Gsf17PlfsI3aQARAQAB
tFZSUE0gRnVzaW9uIG5vbmZyZWUgcmVwb3NpdG9yeSBmb3IgRmVkb3JhICgzMikg
PHJwbWZ1c2lvbi1idWlsZHN5c0BsaXN0cy5ycG1mdXNpb24ub3JnPokCRQQTAQgA
LxYhBP5ak5PLbicbWpDMGw2adpltwb4YBQJcqbQfAhsDBAsJCAcDFQgKAh4BAheA
AAoJEA2adpltwb4YBmMP/R/K7SEr6eOFLt9tmsI06BCOLwYtQw1yBPOP/QcX9vZG
Af6eWk5Otvub38ZKqxkO9j2SdAwr16cDXqL6Vfo45vqRCTaZpOBw2rRQlqgFNvQ2
7uzzUk8xkwAyh3tqcUuJjdPso/k02ZxPC5xR68pjOyyvb618RXxjuaaOHFqt2/4g
LEBGcxfuBsKMwM8uZ5r61YRyZle23Ana8edvVOQWeyzF0hx/WXCRke/nCyDEE6OA
IGhcA0XOjnzzLxTLjvmnjBUaenXnpBS8LA5OPOo0TjvPiAj7DSR8lfQYNorGxisD
cEJm/upsJii/x3Tm4dwRvlmvZuw4CC7UCQ3FIu3eAsNoqRAeV8ND33T/L3feHkxj
0fkWwihAcx12ddaRM5iOEMPNmUTyufj9KZy21jAy3AooMiDb8o17u4fb6irUs/YE
/TL1EG2W8L7R6idgjk//Ip8sNvxr3nwmyv7zJ6vWfhuS/inuEDdvHqqrs+s5n4gk
jTKf3If3e6unzMNO5945DgvXcx09G0QqgdrRLprT+bj6581YbOnzvZdUqgOaw3M5
pGdE6wHro7qtbp/HolJYx07l0AW3AW9v+mZSIBXp2UyHXzFN5ycwpgXo+rQ9mFP9
wzK/najg8b1aC99psZhS/mVVFVQJC5Ozz4j/AMIaXQPaFhAFd6uRQPu7fZX/kjmN
=U9qR
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$1" > rpmfusion-nonfree.rpm
curl -L "${1/-release-/-release-tainted-}" > rpmfusion-nonfree-tainted.rpm
rpm --checksig --define=_pkgverify_{'flags 0x0','level all'} rpmfusion-nonfree{,-tainted}.rpm
rpm --install rpmfusion-nonfree{,-tainted}.rpm
exec rm -f rpmfusion-nonfree{,-tainted}.rpm
EOF

[[ options[release] -ge DEFAULT_RELEASE ]] ||
. "legacy/${options[distro]}$(( --DEFAULT_RELEASE )).sh"
