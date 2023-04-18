# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=fedora [release]=37).

# Override buildroot creation to set the container image file name.
eval "$(declare -f create_buildroot | $sed 's/cver=.*/cver=1.7/')"

# Override package installation to use the bundled UEFI stub.
eval "$(declare -f create_buildroot | $sed 's/systemd-boot[-a-z]*//')"

# Override UEFI logo generation to support old ImageMagick and systemd.
eval "$(declare -f save_boot_files | $sed "s/magick/convert/
s/-trim/& -color-matrix '0 1 0 0 0 0 1 0 0 0 0 1 1 0 0 0'/")"

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import
        $gpg --verify "$1"
        [[ $($sha256sum "$2") == $($sed -n '/=/{s/.* //p;q;}' "$1")\ * ]]
} << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGESvNwBEAC7HsCDTlugVeDSMFX6aW3zAPFMfvBssNj+89fdmbxcI9t7UY6f
HvkkGziUET8e+9jB8R2/wXQCGOw1J+sfmwO4aN0LdVQjhKvVNj+F5jWt3m5FAIBa
OTWS6Kvqw2ECTpH7fD86541eK3BuCni6d5U3PCd73t976FcUmpQ/1AthqMksM0Jz
cJapvNmLTCR0NZ2XyyLmn/K1hgNXe8G5j0cSrJiY+Zpz5aQkT96j96Jm6W2A+tBI
icU4n6V4vlj2TxmCumtXJGXGBGJnof/dCgh45aqi+sk5c429ns+5sooYcaEJojj6
FYSITv10l+az6ZMJz/j61VYSkhMY8hQ4Wd+yL2JVzLE9N9V0L95sX1yEZ5ILmzwx
oRKe4WHSBE6yMxNWobv7hmC+3ZC5mLPaEDS/g/0xuQj9Sy9eT2mhhFPxOv29YQ+P
sC3zXHJMMT0tlGd72PVHQQ0JYONfMhcC+7AHGFGz8p4/wor2jIFG1ouqE6Lfzm8o
XWZMYm3AydlrP/xkYaoWNE3jL/+dskSBr/Yz7ZzlkAqH9lb1HKnXQLTrw6gz6pmI
KufSDXjEFNxnFI/9gMlshJtk5+QSDzezmxFm+NMviSvDUNAVIzrU1D84dauBYph4
OrJVeECQHEotny/I53AdlVwLYB4TWkObzTs6vtV7Pz1TK2CmHpe3UW72xwARAQAB
tDFGZWRvcmEgKDM3KSA8ZmVkb3JhLTM3LXByaW1hcnlAZmVkb3JhcHJvamVjdC5v
cmc+iQJOBBMBCAA4FiEErLXuToMcdLt8Fo0n9VrT+1MjVSoFAmESvNwCGw8FCwkI
BwIGFQoJCAsCBBYCAwECHgECF4AACgkQ9VrT+1MjVSoPMhAAist7kK/YtcyBL/dt
P55hPrkJT6Ay+e2Dvt4Pixe4iT32Y3jG12aoX2LY//mxVOOpV+EhXYTTb5aLt2Jj
a8/qCKJFk7zuCOxa1hgdRcjoR7ZbU0lNjD9mMCax/YT9QafcaMEib/FlknP3g1SN
GRSKLObTJd6BbtZXCE80JRIX+Dy6+/Oz7LXRXeKpiimhlXT1wuTaqAJEtuHdQvg7
dkL4DzAJ2FiURVd5gvgo266WaCMafJjFRrSGHJm0c+V+0Z9NsuH80JbPm+rCUh5U
E9PMyztqlqtldtqc1+aZ1iUbVuXY059BUmlAhmf5sAlBktY+hEabH/4kmfGccbBL
TyBIn03Y9q9173okZSUe6q16m/hbbWI8dwkSpIADZbGGJbRi8PJpCg9y6KI355qD
atE2irleoy6eXqpKa+uPTRBk7i/r6jDoA+u+tZyFfcEnwvSWP8cN1j5mNklvITZl
YF1n5b3fejkZVdOmRZQNkyzMxYEd4UZFQZNYrx0nltAagRS8b5ikqNk2UTl+dyBG
k9gLOSZhAa2JdmAqwe9rT69jaa4kZMLlxPPC3246s83t0s7lp7vF+zLPfPSvxpsU
tg+fuT+OFKWYdBFF7VkEA+wezHAznIP6TPyQXbBpkzE889/hOXy4BYs0wy8Bpda/
Ve2Ba329f99dSCZKImi5DPCxJY4=
=ZmVd
-----END PGP PUBLIC KEY BLOCK-----
EOF

[[ options[release] -ge DEFAULT_RELEASE ]] ||
. "legacy/${options[distro]}$(( --DEFAULT_RELEASE )).sh"
