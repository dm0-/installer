packages=(kernel)  # Not dealing with handling all the old CentOS 7 modules
packages_buildroot=()

DEFAULT_RELEASE=7.6.1810
options[networkd]=
options[release]=$DEFAULT_RELEASE

function create_buildroot() {
        local -r image="https://github.com/CentOS/sig-cloud-instance-images/raw/CentOS-${options[release]:=$DEFAULT_RELEASE}/docker/centos-${options[release]%%.*}-docker.tar.xz"

        opt bootable || opt ramdisk && packages_buildroot+=(kernel)
        opt selinux && packages_buildroot+=(policycoreutils)
        opt squash && packages_buildroot+=(squashfs-tools) || packages_buildroot+=(e2fsprogs)
        opt verity && packages_buildroot+=(veritysetup)
        opt uefi && packages_buildroot+=(centos-logos ImageMagick)

        $mkdir -p "$buildroot"
        $curl -L "$image" > "$output/image.tar.xz"
        $curl -L "$image.asc" | verify_centos - "$output/image.tar.xz"
        $tar -C "$buildroot" -xJf "$output/image.tar.xz"
        $rm -f "$output/image.tar.xz"

        enter /usr/bin/yum --assumeyes upgrade
        test -z "${packages_buildroot[*]:-$*}" ||
        enter /usr/bin/yum --assumeyes install "${packages_buildroot[@]}" "$@"
}

function install_packages() {
        opt bootable && packages+=(systemd)
        opt iptables && packages+=(iptables-services NetworkManager)  # No networkd on CentOS 7
        opt selinux && packages+=(selinux-policy-targeted)

        yum --assumeyes --installroot="$PWD/root" \
            --releasever="${options[release]%%.*}" \
            install "${packages[@]}" "$@"

        rpm -qa | sort > packages-buildroot.txt
        rpm --root="$PWD/root" -qa | sort > packages.txt
}

function save_boot_files() {
        sed -i -e 's/^[# ]*\(filesystems+=\).*/\1"squashfs"/' /etc/dracut.conf
        dracut --force /boot/initrd.img "$(cd /lib/modules ; echo *)"

        opt uefi && convert -background none /usr/share/centos-logos/fedora_logo_darkbackground.svg logo.bmp

        cp -p /boot/vmlinuz-* vmlinuz
        cp -pt . /boot/initrd.img
}

function distro_tweaks() {
        test -e root/etc/sysconfig/network ||
        touch root/etc/sysconfig/network
}

function relabel() { : ; }

# No zstd on CentOS 7
function squash() {
        local -r IFS=$'\n' xattrs=-$(opt selinux || echo no-)xattrs
        mksquashfs root "$disk" -noappend "$xattrs" -comp xz \
            -wildcards -ef /dev/stdin <<< "${exclude_paths[*]}"
}

function verify_centos() {
        local -rx GNUPGHOME="$output/gnupg"
        trap "$rm -fr $GNUPGHOME" RETURN
        $mkdir -pm 0700 "$GNUPGHOME"
        $gpg --import << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFOn/0sBEADLDyZ+DQHkcTHDQSE0a0B2iYAEXwpPvs67cJ4tmhe/iMOyVMh9
Yw/vBIF8scm6T/vPN5fopsKiW9UsAhGKg0epC6y5ed+NAUHTEa6pSOdo7CyFDwtn
4HF61Esyb4gzPT6QiSr0zvdTtgYBRZjAEPFVu3Dio0oZ5UQZ7fzdZfeixMQ8VMTQ
4y4x5vik9B+cqmGiq9AW71ixlDYVWasgR093fXiD9NLT4DTtK+KLGYNjJ8eMRqfZ
Ws7g7C+9aEGHfsGZ/SxLOumx/GfiTloal0dnq8TC7XQ/JuNdB9qjoXzRF+faDUsj
WuvNSQEqUXW1dzJjBvroEvgTdfCJfRpIgOrc256qvDMp1SxchMFltPlo5mbSMKu1
x1p4UkAzx543meMlRXOgx2/hnBm6H6L0FsSyDS6P224yF+30eeODD4Ju4BCyQ0jO
IpUxmUnApo/m0eRelI6TRl7jK6aGqSYUNhFBuFxSPKgKYBpFhVzRM63Jsvib82rY
438q3sIOUdxZY6pvMOWRkdUVoz7WBExTdx5NtGX4kdW5QtcQHM+2kht6sBnJsvcB
JYcYIwAUeA5vdRfwLKuZn6SgAUKdgeOtuf+cPR3/E68LZr784SlokiHLtQkfk98j
NXm6fJjXwJvwiM2IiFyg8aUwEEDX5U+QOCA0wYrgUQ/h8iathvBJKSc9jQARAQAB
tEJDZW50T1MtNyBLZXkgKENlbnRPUyA3IE9mZmljaWFsIFNpZ25pbmcgS2V5KSA8
c2VjdXJpdHlAY2VudG9zLm9yZz6JAjUEEwECAB8FAlOn/0sCGwMGCwkIBwMCBBUC
CAMDFgIBAh4BAheAAAoJECTGqKf0qA61TN0P/2730Th8cM+d1pEON7n0F1YiyxqG
QzwpC2Fhr2UIsXpi/lWTXIG6AlRvrajjFhw9HktYjlF4oMG032SnI0XPdmrN29lL
F+ee1ANdyvtkw4mMu2yQweVxU7Ku4oATPBvWRv+6pCQPTOMe5xPG0ZPjPGNiJ0xw
4Ns+f5Q6Gqm927oHXpylUQEmuHKsCp3dK/kZaxJOXsmq6syY1gbrLj2Anq0iWWP4
Tq8WMktUrTcc+zQ2pFR7ovEihK0Rvhmk6/N4+4JwAGijfhejxwNX8T6PCuYs5Jiv
hQvsI9FdIIlTP4XhFZ4N9ndnEwA4AH7tNBsmB3HEbLqUSmu2Rr8hGiT2Plc4Y9AO
aliW1kOMsZFYrX39krfRk2n2NXvieQJ/lw318gSGR67uckkz2ZekbCEpj/0mnHWD
3R6V7m95R6UYqjcw++Q5CtZ2tzmxomZTf42IGIKBbSVmIS75WY+cBULUx3PcZYHD
ZqAbB0Dl4MbdEH61kOI8EbN/TLl1i077r+9LXR1mOnlC3GLD03+XfY8eEBQf7137
YSMiW5r/5xwQk7xEcKlbZdmUJp3ZDTQBXT06vavvp3jlkqqH9QOE8ViZZ6aKQLqv
pL+4bs52jzuGwTMT7gOR5MzD+vT0fVS7Xm8MjOxvZgbHsAgzyFGlI1ggUQmU7lu3
uPNL0eRx4S1G4Jn5
=OGYX
-----END PGP PUBLIC KEY BLOCK-----
EOF
        $gpg --verify "$@"
}
