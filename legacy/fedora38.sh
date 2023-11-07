# SPDX-License-Identifier: GPL-3.0-or-later
declare -f verify_distro &> /dev/null  # Use ([distro]=fedora [release]=38).

# Override buildroot creation to set the container image file name.
eval "$(declare -f create_buildroot | $sed 's/cver=.*/cver=1.6/')"

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- '$rm -fr "$GNUPGHOME" ; trap - RETURN' RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import
        $gpg --verify "$1"
        [[ $($sha256sum "$2") == $($sed -n '/=/{s/.* //p;q;}' "$1")\ * ]]
} << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGIC2cYBEADJye1aE0AR17qwj6wsHWlCQlcihmqkL8s4gbOk1IevBbH4iXJx
lu6bN+NhTcCCX6eHmaL5Pwb/bpkMmLR+/r1D2cLDK24YzvN6kJnwRQUTf2dbqYmg
mNBgIMm+kAabBZPwUHUzyQ9CT/WJpYr1OYu8JIkdxF35nrPewnnOUUqxqbi8fXRQ
gskSLF8UveiOjFIqmWwlPwT1UtnevAaF80UGQlkwFvqjjh4b9vKY2gHMAQwt+wg5
HFFCSwSrnd88ZoDb3pKvDMeurYUiPzF5f2r+ziVkMuaSNckvp58uge7HvyqQPAdJ
ZRswCCxhUAo9VqkNfB4Ud25ASyalk9jOE3HB8E35gFfPXvuX1n15THXNcwMEiybk
Omne2YwXL8ShGNr5otjqywThMrrqcl2g/pJVTcpDHTR5Hn9YRp+GHlYLjyEr+/x7
xM19y9ca9GUiJqDbEREHcKKIhYiGmcIjjcJvei/3C/aM4pqeGFJBbVSnw3qeMxH/
6ArAMA1sAdShCkv2YjlcF0r4uoCjXdS3xrKLz9PSCquot7RySnOE9TZ7flfJll7Z
q+lNaSeJg7FK8VWSUb9Lit6VEYVbzWKzespDDbujrHbFpydyq8gXurk7bSR2w0te
gsmytQqT/w1z2bydgGF6SfY9Px0wuA8GQKr48l5Bhdc6+vHHFqPKzz0PVQARAQAB
tDFGZWRvcmEgKDM4KSA8ZmVkb3JhLTM4LXByaW1hcnlAZmVkb3JhcHJvamVjdC5v
cmc+iQJOBBMBCAA4FiEEalG7q7o9VGe2FxIhgJqNfOsQtGQFAmIC2cYCGw8FCwkI
BwIGFQoJCAsCBBYCAwECHgECF4AACgkQgJqNfOsQtGScyw/7BLmD4Fwi4QZY94zl
vlJdNufZRavOemSIVVDHoCr8pQBAdrvoMypxJd5zM4ODIqFsjdYpFti+Tkeq4/4U
25UoLPEOtU8UDt2uq7LqfdCxspaj7VyXAJIkpf7wEvLS4Jzo+YaMIlsd0dCrMXTM
vhu4gKpBFW6C+gGlmuDyTJbyrf7ilytgVzVtIfRrT7XffylviIlZHwKm43UDjvzX
YEl3EAFR1RjATwXMy2aJh7GCNsz+fKs+7YRKQUhpMF5un/2pyNJO+LbVGGwGZvga
K9Kfsg/4r1ync4nDDD1dadKIHhobDeiJ9uZLoBvvVDz7Ywu7q/vv4zIPxstYBNq4
6fLKDtYXuJCK0EV9Qy4ox67t0UGlaRGH8y5YUqOI10xH7iQej0xWlSc8w2dKhPz8
z9XLv2OMK+PvqvflhFHhWkqEoQRqTu0TVD0fLLe4lqieJlqZcJqW0F9G/vNSSWmf
POLa/Nim71gL2fPjCJOIRV4K/cJSyBmu5NchG7dHD5sUtJxZ4TFSuepaBZ8cPK1x
e26TaCBqoUWgUXWmw+P89aOpYOJYEFfT/VAm2Ywn+c1EFUmD+30wQ7aP/RUFl94z
n0BjqsWDnCKVFHydZ0TZSpeADmXMg2VYZPcp/cQR1KjoBoDxAscis7b1XPQUg7CB
zquq5jBVAnsNIhs7g47GWKyDUJM=
=aCLl
-----END PGP PUBLIC KEY BLOCK-----
EOF

[[ options[release] -ge DEFAULT_RELEASE ]] ||
. "legacy/${options[distro]}$(( --DEFAULT_RELEASE )).sh"
