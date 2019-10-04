. fedora.sh  # Inherit Fedora's RPM functions.

packages=()
packages_buildroot=()

DEFAULT_RELEASE=7.6.1810
options[networkd]=
options[release]=$DEFAULT_RELEASE
options[uefi]=

function create_buildroot() {
        local -r image="https://github.com/CentOS/sig-cloud-instance-images/raw/CentOS-${options[release]:=$DEFAULT_RELEASE}/docker/centos-${options[release]%%.*}-docker.tar.xz"

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
        opt bootable && opt verity && echo 'add_dracutmodules+=" dm "' \
            >> "$buildroot/etc/dracut.conf.d/99-settings.conf"

        enter /usr/bin/yum --assumeyes upgrade
        enter /usr/bin/yum --assumeyes install "${packages_buildroot[@]}" "$@"

        # Let the configuration decide if the system should have documentation.
        $sed -i -e '/^tsflags=/d' "$buildroot/etc/yum.conf"
}

function install_packages() {
        opt bootable && packages+=(systemd)
        opt iptables && packages+=(iptables-services NetworkManager)  # No networkd on CentOS 7
        opt selinux && packages+=(selinux-policy-targeted)

        mkdir -p root/var/cache/yum
        mount --bind /var/cache/yum root/var/cache/yum
        trap -- 'umount root/var/cache/yum' RETURN

        yum --assumeyes --installroot="$PWD/root" \
            --releasever="${options[release]%%.*}" \
            install "${packages[@]:-filesystem}" "$@"

        rpm -qa | sort > packages-buildroot.txt
        rpm --root="$PWD/root" -qa | sort > packages.txt
}

function distro_tweaks() {
        mkdir -p root/usr/lib/systemd/system/local-fs.target.wants
        ln -fst root/usr/lib/systemd/system/local-fs.target.wants ../tmp.mount

        test -e root/etc/sysconfig/network ||
        touch root/etc/sysconfig/network

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

function relabel() if opt selinux
then
        local -r kernel=vmlinuz$(test -s vmlinuz.relabel && echo .relabel)
        local -r root=$(mktemp --directory --tmpdir="$PWD" relabel.XXXXXXXXXX)
        mkdir -p "$root"/{bin,dev,etc,lib,lib64,proc,sys,sysroot}
        ln -fst "$root/etc" ../sysroot/etc/selinux

        cat << 'EOF' > "$root/init" && chmod 0755 "$root/init"
#!/bin/bash -eux
export PATH=/bin
mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
for mod in crct10dif_common crc-t10dif sd_mod libata ata_piix jbd2 mbcache ext4
do insmod "/lib/$mod.ko"
done
mount /dev/sda /sysroot
load_policy -i
setfiles -vFr /sysroot{,/etc/selinux/targeted/contexts/files/file_contexts,}
umount /sysroot
echo o > /proc/sysrq-trigger
exec sleep 60
EOF

        cp -t "$root/bin" \
            /usr/*bin/{bash,load_policy,mount,setfiles,sleep,umount}
        cp /usr/bin/kmod "$root/bin/insmod"
        find /usr/lib/modules/*/kernel '(' \
            -name crct10dif_common.ko.xz -o -name crc-t10dif.ko.xz -o -name sd_mod.ko.xz -o \
            -name libata.ko.xz -o -name ata_piix.ko.xz -o \
            -name ext4.ko.xz -o -name jbd2.ko.xz -o -name mbcache.ko.xz -o \
            -false ')' -exec cp -at "$root/lib" '{}' +
        unxz "$root"/lib/*.xz

        { ldd "$root"/bin/* || : ; } |
        sed -n 's,^[^/]\+\(/[^ ]*\).*,\1,p' | sort -u |
        while read -rs ; do cp "$REPLY" "$root$REPLY" ; done

        find "$root" -mindepth 1 -printf '%P\n' |
        { cd "$root" ; cpio -H newc -R 0:0 -o ; } |
        xz --check=crc32 -9e > relabel.img

        umount root ; trap - EXIT
        /usr/libexec/qemu-kvm -nodefaults -m 1G -serial stdio < /dev/null \
            -kernel "$kernel" -append console=ttyS0 \
            -initrd relabel.img /dev/loop-root
        mount /dev/loop-root root ; trap -- 'umount root' EXIT
fi

function squash() if opt squash
then
        local -r IFS=$'\n' xattrs=-$(opt selinux || echo no-)xattrs
        disk=squash.img
        mksquashfs root "$disk" -noappend "$xattrs" -comp xz \
            -wildcards -ef /dev/stdin <<< "${exclude_paths[*]}"
fi

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
        local -r url="https://dl.fedoraproject.org/pub/epel/epel-release-latest-${options[release]%%.*}.noarch.rpm"
        script << EOF
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
        local -r url="https://download1.rpmfusion.org/free/el/updates/${options[release]%%.*}/x86_64/r/rpmfusion-free-release-${options[release]%%.*}-4.noarch.rpm"
        enable_epel
        script << EOF
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
curl -L "${url/-free-release-/-free-release-tainted-}" > rpmfusion-free-tainted.rpm
rpm --checksig rpmfusion-free{,-tainted}.rpm
rpm --install rpmfusion-free{,-tainted}.rpm
exec rm -f rpmfusion-free{,-tainted}.rpm
EOF
}

# OPTIONAL (IMAGE)

eval "_$(declare -f store_home_on_var)"
function store_home_on_var() {
        "_${FUNCNAME[0]}" "$@"
        sed -i -e 's/^Q /d /' root/usr/lib/tmpfiles.d/home.conf
}

# WORKAROUNDS

function systemd-sysusers() { : ; }
