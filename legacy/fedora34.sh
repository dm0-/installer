# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=fedora [release]=34).

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import
        $gpg --verify "$1"
        [[ $($sha256sum "$2") == $($sed -n '/=/{s/.* //p;q;}' "$1")\ * ]]
} << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBF8sAZIBEADKYvLg/5FdLXcVryAFd7Q8qrJq23R7ebxUT1u48Dc8xrsfYJZq
aMcna/xw47wZNyek4Z6YpzqfmnjR7H8yRH/1hAPi/ixYnA6DVL7O3eGE5lYGJzN3
E2ILTzBOI9o/pavvtOqW9N5WIus8cqSdA921v8YPzr3/BTKgGqC9biOrMA+3sNoe
U4T+dztLg20SyBTr/rBH0eui2p/ipvIRuJvHLTKTubR+yG804yupI69M6qFBDebT
rm+CBmwVyj/DY/92LgvCgYqV/TL5FU4qvtyB6jd8JkEeaz/G7UmDRB5JqzKEu6TB
N3SY7nwLiRpIaXet1TWVW/8UKSB2JvYt1LbZyEO82/QOIXxqvV6h3kuBI21RvURz
VxEjRlvPRGHMZ80OoAQqNPkLnVTcX1eLj2ClbwoXCmXFSm72cCCt1SzcAmlaWh8E
rXSUZfs7XqkBrbphXHZ1e6Vxjt/RyKC5doklfOhbuF8gJ31CPo/kuOjFrHGzOwgi
Llec+GHGMfI/cUOu59qo3W85GHsntvEMk83QLkKjBInEYjZSAajp/lS4QF+SD4pl
Qj6Vc1mMCmci61cXX5CcIl1YxNJZzUfZEZNbUjDajqGzkYJoG9n2yJB0w4OiqsAe
ZCirmUIeDUNeI082epc4RFuV33hByGYY9kRWSyM+aCF6PYVISj4l1o9KcQARAQAB
tDFGZWRvcmEgKDM0KSA8ZmVkb3JhLTM0LXByaW1hcnlAZmVkb3JhcHJvamVjdC5v
cmc+iQJOBBMBCAA4FiEEjFummQvbJuGfKhqAEWGuaUVxmjkFAl8sAZICGw8FCwkI
BwIGFQoJCAsCBBYCAwECHgECF4AACgkQEWGuaUVxmjlVuA//QnMA02tydqwpM7r4
WZ4OvlVqFWHhn3oDaBSwBvn6R1oC0MWbr79nnFDn3tpSkZDUdb7wyArmaF8kG8tI
wit5xD/JAzqRBVa9z2hY3n1SFafU/hp3DwbGIL4vLUv3fRayCgWsGhGp0tZvDC9q
PSvQZ675XpRG4pt/TGJB5gGXw7Jxoae/ffaJeblLLRDlSV/bKJt9sYpdu5InDG2i
yIUHfamtYQtnENKL/bN6w7tU/IEgCHqxPmPRiJ0gTUAi5Yabp1+JHqskE85Hm2QF
xMonX595Ry1yZzCjPGhCPAknJ4BhisXV+E/iV3Jyh8vxbJCo1//ygd1Xz8SkCuu/
I0xPtFcVSIP2ikYpJwR2nwwQlLbQYIGCw/S1LV725oEYm/Z1xQ5zha2hBB+fxSwz
7MHsD2XIHrP8NNwt3ywG3NV/BSSkvSSStGUNcQyGRi3O/x/BEIRtWRxgoNO9o3jE
xtWFq3G5+gKY+wfYz/cTGlsWPDG7Fzx4lNisIGATKtLNqdedl7LASPK93z0XDdnS
kfKF0HrT9rdzIKRu4xWatUVIq/65Gv7nsavdsRAQL/Y0jl6sjjQac/Te5J0fByHY
6tGG1W0UWTd0rzFWitEZI/64/Bs83rGhjJNLqWXItZ5VqLe0TWzuxvRFLfM7oX8r
n5Si4l7NpIJubWPqjPoCoP5lsS8=
=V2FG
-----END PGP PUBLIC KEY BLOCK-----
EOF

[[ options[release] -ge DEFAULT_RELEASE ]] ||
. "legacy/fedora$(( --DEFAULT_RELEASE )).sh"
