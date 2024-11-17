# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=fedora [release]=40).

# Override buildroot creation to use the pre-dnf5 container format.
eval "$(declare -f create_buildroot | $sed 's/cver=.*/cver=1.14/
/image=/{s/-Minimal-\([^.]*\)\.\([^.]*\)/.\2-\1/;}')"

# Override package installation to go back to pre-dnf5.
eval "$(declare -f install_packages |
$sed 's/libdnf5/dnf/g;s/ --use-host-config / /')"

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import
        $gpg --verify "$1"
        [[ $($sha256sum "$2") == $($sed -n '/Generic\..*=/{s/.* //p;q;}' "$1")\ * ]]
} << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGPQTCwBEADFUL0EQLzwpKHtlPkacVI156F2LnWp6K69g/6yzllidHI3b7EV
QgQ9/Kdou6wNuOahNKa6WcEi6grEXexD7pAcu4xdRUp79XxQy5pC7Aq2/Dwf0vRL
2y0kqof+C7iSzhHsfLoaqKKeh2njAo1KLZXYTHAWAMbXEyO/FJevaHLXe2+yYd7j
luD58gyXgGDXXJ2lymLqs2jobjWdmGPNZGFl36RP3Dnk0FpbdH78kyIIsc2foYuF
00rnuumwCtK3V58VOZo6IkaYk2irdyeetmJjVHwLHwJB3EaAwGy9Z2oAH3LxxFfk
rQb0DH0Nzb3fpEziopOOqSi+6guV4RHUKAkCUMu+Mo5XwFVPUAIfNRTVqoIaEasC
WO26lhkB87wwIvyb/TPGSeh6laHPRf0QOUOLkugdkSHoaJFWoTCcu9Y4aeDpf+ZQ
fMVmkJNRS1tXONgz+pDk1rro/tNrkusYG18xjvSZTB0P0C4b4+jgK5l7me0NU6G3
Ww/hIng5lxWfXgE9bpxlN834v1xy5Z3v17guJu1ec/jzKzQQ4356wyegXURjYoWe
awcnK1S+9gxivnkOk1bGLNxrEh5vB6PDcI1VQ1ECH50EHyvE1IXJDaaStdAkacv2
qHcd15CnlBW1LYFj0CHs/sGu9FD0iSF95OVRX4gjg9Wa4f8KvtEO/f+FeQARAQAB
tDFGZWRvcmEgKDQwKSA8ZmVkb3JhLTQwLXByaW1hcnlAZmVkb3JhcHJvamVjdC5v
cmc+iQJOBBMBCAA4FiEEEV35rvhXhT7oRF0KBydwfqFbecwFAmPQTCwCGw8FCwkI
BwIGFQoJCAsCBBYCAwECHgECF4AACgkQBydwfqFbecxJOw//XaoJG3zN01bVM63H
nFmMW/EnLzKrZqH8ZNq8CP9ycoc4q8SYcMprHKG9jufzj5/FhtpYecp3kBMpSYHt
Vu46LS9NajJDwdfvUMezVbieNIQ8icTR5s5IUYFlc47eG6PRe3k0n5fOPcIb6q82
byrK3dQnanOcVdoGU7QO9LAAHO9hg0zgZa0MxQAlDQov3dZcr7u7qGcQmU5JzcRS
JgfDxHxDuMjmq6Kd0/UwD00kd2ptZgRls0ntXdm9CZGtQ/Q0baJ3eRzccpd/8bxy
RWF9MnOdmV6ojcFKYECjEzcuheUlcKQH9rLkeBSfgrIlK3L7LG8bg5ouZLdx17rQ
XABNQGmJTaGAiEnS/48G3roMS8R7fhUljcKr6t63QQQJ2qWdPvI6EMC2xKZsLHK4
XiUvrmJpUprvEQSKBUOf/2zuXDBshtAnoKh7h5aG+TvozL4yNG5DKpSH3MRj1E43
KoMsP/GN/X5h+vJnvhiCWxNMPP81Op0czBAgukBm627FTnsvieJOOrzyxb1s75+W
56gJombmhzUfzr88AYY9mFy7diTw/oldDZcfwa8rvOAGJVDlyr2hqkLoGl+5jPex
slt3NF4caE/wP9wPMgFRkmMOr8eiRhjlWLrO6mQdBp7Qsj3kEXioP+CZ1cv/sbaK
4DM7VidB4PLrMFQMaf0LpjpC2DM=
=wOl2
-----END PGP PUBLIC KEY BLOCK-----
EOF

[[ options[release] -ge DEFAULT_RELEASE ]] ||
. "legacy/${options[distro]}$(( --DEFAULT_RELEASE )).sh"
