declare -f verify_distro &> /dev/null  # Use ([distro]=centos [release]=7).

packages=()
packages_buildroot=()

DEFAULT_RELEASE=7
options[uefi]=

function create_buildroot() {
        local -r image="https://github.com/CentOS/sig-cloud-instance-images/raw/CentOS-${options[release]:=$DEFAULT_RELEASE}-$DEFAULT_ARCH/docker/centos-${options[release]}-$DEFAULT_ARCH-docker.tar.xz"

        opt bootable && packages_buildroot+=(kernel microcode_ctl)
        opt selinux && packages_buildroot+=(kernel policycoreutils qemu-kvm)
        opt squash && packages_buildroot+=(squashfs-tools)
        opt verity && packages_buildroot+=(veritysetup)
        opt uefi && packages_buildroot+=(centos-logos ImageMagick)
        packages_buildroot+=(e2fsprogs)

        $mkdir -p "$buildroot"
        $curl -L "$image" > "$output/image.tar.xz"
        $curl -L "$image.asc" | verify_distro - "$output/image.tar.xz"
        $tar -C "$buildroot" -xJf "$output/image.tar.xz"
        $rm -f "$output/image.tar.xz"

        configure_initrd_generation

        enter /usr/bin/yum --assumeyes upgrade
        enter /usr/bin/yum --assumeyes install "${packages_buildroot[@]}" "$@"

        # Let the configuration decide if the system should have documentation.
        $sed -i -e '/^tsflags=/d' "$buildroot/etc/yum.conf"
}

function install_packages() {
        opt bootable && packages+=(systemd)
        opt selinux && packages+=(selinux-policy-targeted)

        mkdir -p root/var/cache/yum
        mount --bind /var/cache/yum root/var/cache/yum
        trap -- 'umount root/var/cache/yum' RETURN

        yum --assumeyes --installroot="$PWD/root" \
            --releasever="${options[release]}" \
            install "${packages[@]:-filesystem}" "$@"

        rpm -qa | sort > packages-buildroot.txt
        rpm --root="$PWD/root" -qa | sort > packages.txt
}

function distro_tweaks() {
        rm -fr root/etc/chkconfig.d root/etc/init{.d,tab} root/etc/rc{.d,.local,[0-6].d}

        mkdir -p root/usr/lib/systemd/system/local-fs.target.wants
        ln -fst root/usr/lib/systemd/system/local-fs.target.wants ../tmp.mount

        sed -i -e 's/^[^#]*PS1="./&\\$? /;s/mask 002$/mask 022/' root/etc/bashrc
}

function save_boot_files() if opt bootable
then
        opt uefi && convert -background none /usr/share/centos-logos/fedora_logo_darkbackground.svg logo.bmp
        cp -p /boot/vmlinuz-* vmlinuz
        cp -p /boot/initramfs-* initrd.img
        cp -pt . root/etc/os-release
elif opt selinux
then cp -p /boot/vmlinuz-* vmlinuz.relabel
fi

# Override ext4 file system handling to work with old CentOS 7 command options.
eval "$(
declare -f mount_root | $sed 's/ount -o X-mount.mkdir /kdir -p root ; mount /'
declare -f unmount_root | $sed 's/tune2fs -O read-only/: &/'
)"

# Override the SELinux labeling VM to add more old CentOS 7 kernel modules.
eval "$(declare -f relabel | $sed '
s/\(-name \)\?sd_mod\(.ko.xz -o\)\?/\1crct10dif_common\2 \1crc-t10dif\2 &/')"

# Override initrd creation to work with old CentOS 7 command options.
eval "$(declare -f build_ramdisk relabel |
$sed 's/cpio -D \([^ ]*\) \([^|]*\)|/{ cd \1 ; cpio \2 ; } |/')"

# Override initrd configuration to add device mapper support when needed.
eval "$(declare -f configure_initrd_generation | $sed /hostonly=/r<(echo \
    "opt verity && echo 'add_dracutmodules+=\" dm \"'" \
    '>> "$buildroot/etc/dracut.conf.d/99-settings.conf"'))"

function verify_distro() {
        local -rx GNUPGHOME="$output/gnupg"
        trap -- "$rm -fr $GNUPGHOME" RETURN
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

# OPTIONAL (BUILDROOT)

function enable_epel() {
        local -r key="RPM-GPG-KEY-EPEL-${options[release]}"
        local -r url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-${options[release]}.noarch.rpm"
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script << EOF
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFKuaIQBEAC1UphXwMqCAarPUH/ZsOFslabeTVO2pDk5YnO96f+rgZB7xArB
OSeQk7B90iqSJ85/c72OAn4OXYvT63gfCeXpJs5M7emXkPsNQWWSju99lW+AqSNm
jYWhmRlLRGl0OO7gIwj776dIXvcMNFlzSPj00N2xAqjMbjlnV2n2abAE5gq6VpqP
vFXVyfrVa/ualogDVmf6h2t4Rdpifq8qTHsHFU3xpCz+T6/dGWKGQ42ZQfTaLnDM
jToAsmY0AyevkIbX6iZVtzGvanYpPcWW4X0RDPcpqfFNZk643xI4lsZ+Y2Er9Yu5
S/8x0ly+tmmIokaE0wwbdUu740YTZjCesroYWiRg5zuQ2xfKxJoV5E+Eh+tYwGDJ
n6HfWhRgnudRRwvuJ45ztYVtKulKw8QQpd2STWrcQQDJaRWmnMooX/PATTjCBExB
9dkz38Druvk7IkHMtsIqlkAOQMdsX1d3Tov6BE2XDjIG0zFxLduJGbVwc/6rIc95
T055j36Ez0HrjxdpTGOOHxRqMK5m9flFbaxxtDnS7w77WqzW7HjFrD0VeTx2vnjj
GqchHEQpfDpFOzb8LTFhgYidyRNUflQY35WLOzLNV+pV3eQ3Jg11UFwelSNLqfQf
uFRGc+zcwkNjHh5yPvm9odR1BIfqJ6sKGPGbtPNXo7ERMRypWyRz0zi0twARAQAB
tChGZWRvcmEgRVBFTCAoNykgPGVwZWxAZmVkb3JhcHJvamVjdC5vcmc+iQI4BBMB
AgAiBQJSrmiEAhsPBgsJCAcDAgYVCAIJCgsEFgIDAQIeAQIXgAAKCRBqL66iNSxk
5cfGD/4spqpsTjtDM7qpytKLHKruZtvuWiqt5RfvT9ww9GUUFMZ4ZZGX4nUXg49q
ixDLayWR8ddG/s5kyOi3C0uX/6inzaYyRg+Bh70brqKUK14F1BrrPi29eaKfG+Gu
MFtXdBG2a7OtPmw3yuKmq9Epv6B0mP6E5KSdvSRSqJWtGcA6wRS/wDzXJENHp5re
9Ism3CYydpy0GLRA5wo4fPB5uLdUhLEUDvh2KK//fMjja3o0L+SNz8N0aDZyn5Ax
CU9RB3EHcTecFgoy5umRj99BZrebR1NO+4gBrivIfdvD4fJNfNBHXwhSH9ACGCNv
HnXVjHQF9iHWApKkRIeh8Fr2n5dtfJEF7SEX8GbX7FbsWo29kXMrVgNqHNyDnfAB
VoPubgQdtJZJkVZAkaHrMu8AytwT62Q4eNqmJI1aWbZQNI5jWYqc6RKuCK6/F99q
thFT9gJO17+yRuL6Uv2/vgzVR1RGdwVLKwlUjGPAjYflpCQwWMAASxiv9uPyYPHc
ErSrbRG0wjIfAR3vus1OSOx3xZHZpXFfmQTsDP7zVROLzV98R3JwFAxJ4/xqeON4
vCPFU6OsT3lWQ8w7il5ohY95wmujfr6lk89kEzJdOTzcn7DBbUru33CQMGKZ3Evt
RjsC7FDbL017qxS+ZVA/HGkyfiu4cpgV8VUnbql5eAZ+1Ll6Dw==
=hdPa
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$url" > epel.rpm
rpm --checksig epel.rpm
rpm --install epel.rpm
exec rm -f epel.rpm
EOF
}

function enable_rpmfusion() {
        local key="RPM-GPG-KEY-rpmfusion-free-el-${options[release]}"
        local url="https://download1.rpmfusion.org/free/el/updates/${options[release]}/$DEFAULT_ARCH/r/rpmfusion-free-release-${options[release]}-4.noarch.rpm"
        enable_epel
        test -s "$buildroot/etc/pki/rpm-gpg/$key" || script << EOF
rpmkeys --import /dev/stdin << 'EOG'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBFVE8DcBEACmsFjnapHXm5l0dXbyxXZU8sZVawRIQ/lG9Yc9tSICcY8QuSxu
636wsVHiQHd0sIipk6vvgWfTTV+w0OxyovY8PFciEtOC4JZBJO1cT952sDxRTzcU
Y+DArqPUwqyMqJo86BxwoQi9qdg4eNlp5RNamzbu2yKpPZUk4RWF0QnlEJ5bQ8xY
Q2HyzR6YUsKBuCbNV/OevxxSjSFesWqmE2zIFVDsNvS+FGbH6SwDrKgBeDHCeg35
KQgHyNkONoe7EjfCVdWwWsOdo9pqEKZKd4U6Sz234d9JqvF7y3+Lc85l/TxU+G/C
uXxRki5XVx3sMH0UgK0nn0fBEv95Dtq5I7EWNYDOesFDbBRjhqo5dh51yOcfn1QO
ATKGwo2WZTGc32kOXwu/zzZaT37HulyOpJ/8jAoOQ6qH5T7RDy2M1vlAvGcdy2dz
GUyD2bNlPSp1exw6CWOXjty/9nOglJBBsr/YwTundSKpZSKPkn3z74ZAD4Pqviwx
yRsk1UjHlCm8sPfahkpRheFKDJT/wIBUhI7tbzyfxMaNwryc1U+yOiAl92sMr8ra
a0CGk48cFa6vulSq/ELdt/qF+I0TywacaTvU3ySSd3Juff54c8ELNBjTGY4MAomk
y1P755q83yBdYaRDU6U1ljKP1GP8Kgilk6QCWu1izFPepPK4Bi7ZGTUEhQARAQAB
tE5SUE0gRnVzaW9uIGZyZWUgcmVwb3NpdG9yeSBmb3IgRUwgKDcpIDxycG1mdXNp
b24tYnVpbGRzeXNAbGlzdHMucnBtZnVzaW9uLm9yZz6JAjIEEwECABwFAlVE8DcC
GwMECwkIBwMVCAoDFgIAAh4BAheAAAoJEHWLPRj1z2weGigQAKO+ULRBzztGDg3m
ev8rDEOfv49x3T4+tTYlMOtvsg8Jvi5okGp+bXO0qZkw8463Ljrs5FAW1/oIGFYA
D9RMDnlgpDAhP6Gho/tGIPc6yfSHOUm2uS5Ve1Q7j3eBHr8IlAvpg/1U9IIS7LDU
WcVNjpsBzog8pGXRBSYx5yi7ddP5GcQPLwn0TT7jkawzrlmfnMz3un6gaxgFIxmS
wzd+lr7CHP3Lptxt3Oe5pliEQ58kuBzt0gkxGkkbeRyolareanJBlIozYIM3TQum
K4UbXIjPWlHr02z+qtrkpkDgM5aO+rEPGctd4W12zT5Gqp5Ij5fuFUHgFKvxf+0F
t7RDWffAiKtk8HX0PoytIBY9fiQtZXjnbPq1rT65brz6bc85HR3sRx2+gn9IN+Cg
OwdV7NoL8Dj7w3J5DMS1yT1KbmwRHHyKD0muL3NUw9RZXPmmUakbIvLZlERKhyca
JZlkakLUOvesXcZg2Zqug36ET0AQO/Af7e6dw8jXBc4BN/R5U8LU0ENaB3apRcdF
NEDqxPo98MGzIxqJUjWkwJfRvdqAPEM8JLeyhcuChsmwIGF0WbLsmVJ90LJxsoZQ
G+iQKiFwF8HO6fBk4APSAtic+j+9uHoLMS9tWsLABmNQCvjtRe6hxz20yud672uo
OEGWGYNPKeu56Dbc18pxBHez9m42
=buWg
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

mQINBFVE8KwBEADAINLGFvBAfBPErA7/zzsGyNgKB1tuyuJVeANZdCxYrWp3G2k0
bwllSkuyBIDLauLzerWsRfNTSW7nAu818G2nfBrX8xUPwCSeECJwUneW0FO72hZ9
NsUXOGC5UShrEcWmjku2ZqsJmDtikUyY6wMsLTiUyooMtwleGu26+nrXKrr7MxAJ
PjNOXwJ1g7LK55Wucv7uhUtRN7ioGUwG24i2pyp9zJ8ElVO8c0BbcfDHYarjYNME
kzalY6N+UQCur5OLkJwI195pqie2TjpyvpG0A+noWpRBV8j6dwrI3fmO2AtAQZdt
39t4AMNoEGiaxClOqeOGPU1zju2cP5EXbCGMKj1pbmvzUdoxknvZJus38s3SjndK
KL9SRwr4e3VOaCZWEDsBQNQvqC3RnPpGbFZksAv6VtgZAzHX1UrYdtxEhWQ+ZXaV
MSbsgJa8ph2dhG1vK6X2z46/zNHU//ESFwmu/jjHWJP2pOEM20yjo3GHX1uBKmuJ
hci2573ZJJubxGf4hSUTylu1lNZ5+SWczQPxyirTZqYwuYV9kdX1kANQ7xCi/2J9
1yOsTyANWlofkCzr4x+sDDjyK5zL9jkleXbKmO+g6nRDIpCvDXCODMT5nfi/+/qY
2FqcwQawhDdKh/U6OQ0N6FM4hhmPTqgtDINnn/m+k1viYv1b0RJcjo+/OwARAQAB
tFFSUE0gRnVzaW9uIG5vbmZyZWUgcmVwb3NpdG9yeSBmb3IgRUwgKDcpIDxycG1m
dXNpb24tYnVpbGRzeXNAbGlzdHMucnBtZnVzaW9uLm9yZz6JAjIEEwECABwFAlVE
8KwCGwMECwkIBwMVCAoDFgIAAh4BAheAAAoJEMj3bfGjEI9sreUP+wXzGVNm5f4v
SsqLGGlGlNIfhtLBBzEX47cbl5qwiT1YoajV6R5ccUeH0oh85Q6sQQ+1VzlTghzi
XdR7HF5HEt3CXLfSIwqlQGjDiwpA8RaohZ3XUmGIsCo+/RhUc2r87MWqXhf1YdEi
0KfI40WQXHPqy+RBbnLHRKHvSY8z/x4aa1jOOfOl/kLo6xjtjtB8su17at9+WPro
fAJOXzM11XYNLDpP3zj8zmY46Fhji03u4URom8AWmxKMebzzv+zCLvjlOodvHjuB
7OQT7uZBjM1DT1saqy0XuANSQNv/ylnhhQ8vnbZxL0IzPWMxGOZjjnY5/ZLLNlmJ
+6qbXLWFM+WeYidM9+yUKK7jLDufGOKvsJMbQug2dgbs9Nkj5aTRQfRBv5szwRoi
xKhyyar9tJp1WjnKcmh9lVMuXqrQ4C7LEJp9SiDhdjXNojKjnwlKHSSKgQ8iBIF6
1rMOc4IaaGSJpWMuCRHPckZPwxxeeRiAYOH3MUbe2eJZZnQLVJH5IahokjMgOGFi
kOvnMlvsXRWbp0NBtRDBrtk2+w/pbqnOCbEKPBKdupeo2M4Zc2EE8arxiswRT4G+
StgWlrhjmlGJbTkngGK4cHrf5cwgEDNdM60io4EVRJ9B3LcjJdFMIC0Ep4/28+vw
LMOlOqkf/TTZWb3HXsWQgLt6zIWSi6pS
=h3MJ
-----END PGP PUBLIC KEY BLOCK-----
EOG
curl -L "$url" > rpmfusion-nonfree.rpm
curl -L "${url/-release-/-release-tainted-}" > rpmfusion-nonfree-tainted.rpm
rpm --checksig rpmfusion-nonfree{,-tainted}.rpm
rpm --install rpmfusion-nonfree{,-tainted}.rpm
exec rm -f rpmfusion-nonfree{,-tainted}.rpm
EOF
}

# OPTIONAL (IMAGE)

# Override the tmpfiles leaf quota group since CentOS 7 systemd is too old.
eval "$(declare -f store_home_on_var | $sed 's/Q /d /')"

# WORKAROUNDS

# CentOS 7 is too old to provide sysusers, so just pretend it always works.
function systemd-sysusers() { : ; }
