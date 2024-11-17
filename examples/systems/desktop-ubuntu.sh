# SPDX-License-Identifier: GPL-3.0-or-later
# This is a standalone Ubuntu workstation image that aims to demonstrate an
# alternative to the Fedora workstation example.  It should be approximately
# equivalent so that they are interchangeable.
#
# The proprietary NVIDIA drivers are optionally installed here.  A numeric
# option value selects the driver branch version, and a non-numeric value
# defaults to the latest.

options+=(
        [distro]=ubuntu
        [gpt]=1                 # Generate a ready-to-boot full disk image.
        [rootmod]=virtio_blk    # Support root on a VirtIO disk.
        [selinux]=default       # Load this SELinux policy in permissive mode.
        [squash]=1              # Use a compressed file system to save space.
        [uefi]=1                # Create a UEFI executable to boot this image.
        [verity]=1              # Prevent the file system from being modified.
)

packages+=(
        linux-image-generic dracut

        # Utilities
        binutils
        bzip2
        console-data
        emacs-nox
        file
        findutils
        git
        grep
        gzip
        kbd
        less
        lsof
        man{-db,pages}
        p7zip-full
        procps
        sed
        strace
        tar
        unzip
        xz-utils
        ## Accounts
        sudo
        ## Hardware
        pciutils
        usbutils
        ## Network
        iproute2
        iptables-persistent
        net-tools
        openssh-client
        tcpdump
        traceroute
        wget

        # Disks
        cryptsetup
        dosfstools
        e2fsprogs
        hdparm
        lvm2
        mdadm
        squashfs-tools
        sshfs

        # Host
        ovmf
        qemu-{kvm,system-gui}
        systemd-container

        # GNOME
        adwaita-icon-theme-full
        eog
        evince
        gdm3
        gjs
        gnome-backgrounds
        gnome-calculator
        gnome-clocks
        gnome-control-center
        gnome-screenshot
        gnome-session
        gnome-terminal
        gucharmap
        network-manager-gnome
        pipewire-pulse
        wireplumber

        # Graphics
        mesa-{va,vdpau,vulkan}-drivers
        xserver-xorg-{input-libinput,video-{amdgpu,intel,nouveau}}

        # Fonts
        fonts-cantarell
        fonts-dejavu
        fonts-liberation2
        fonts-stix

        # Browser
        firefox

        # VLC
        vlc
)

# Install proprietary NVIDIA drivers.  Also update the buildroot for dracut.
function initialize_buildroot() if opt nvidia
then
        local -r driver_version=${options[nvidia]/#*[!0-9]*/560}
        packages+=(
                "linux-modules-nvidia-$driver_version-generic"
                "xserver-xorg-video-nvidia-$driver_version"
        )
        packages_buildroot+=("linux-modules-nvidia-$driver_version-generic")
fi

# Enable a repository to install a real Firefox package.
function customize_buildroot() {
        enable_repo_ppa mozillateam << 'EOF'
-----BEGIN PGP PUBLIC KEY BLOCK-----

mQINBGYov84BEADSrLhiWvqL3JJ3fTxjCGD4+viIUBS4eLSc7+Q7SyHm/wWfYNwT
EqEvMMM9brWQyC7xyE2JBlVk5/yYHkAQz3f8rbkv6ge3J8Z7G4ZwHziI45xJKJ0M
9SgJH24WlGxmbbFfK4SGFNlg9x1Z0m5liU3dUSfhvTQdmBNqwRCAjJLZSiS03IA0
56V9r3ACejwpNiXzOnTsALZC2viszGiI854kqhUhFIJ/cnWKSbAcg6cy3ZAsne6K
vxJVPsdEl12gxU6zENZ/4a4DV1HkxIHtpbh1qub1lhpGR41ZBXv+SQhwuMLFSNeu
UjAAClC/g1pJ0gzI0ko1vcQFv+Q486jYY/kv+k4szzcB++nLILmYmgzOH0NEqT57
XtdiBWhlb6oNfF/nYZAaToBU/QjtWXq3YImG2NiCUrCj9zAKHdGUsBU0FxN7HkVB
B8aF0VYwB0I2LRO4Af6Ry1cqMyCQnw3FVh0xw7Vz4gQ57acUYeAJpT68q8E2XcUx
riEP65/MBPoFlANLVMSrnsePEXmVzdysmXKnFVefeQ4E3dIDufXUIhrfmL1pMdTG
anhmDEjY7I3pQQQIaLpnNhhSDZKDSk9C/Ax/8gEUgnnmd6BwZxh8Q7oDXcm2tyeu
n2m9wCZI/eJI9P9G8ON8AkKvG4xFR+eqhowwzu7TLDr3feliG+UN+mJ8jwARAQAB
tB5MYXVuY2hwYWQgUFBBIGZvciBNb3ppbGxhIFRlYW2JAk4EEwEKADgWIQRzi+uT
IdGq7BPqk5GuvfSBm+IYZwUCZii/zgIbAwULCQgHAgYVCgkICwIEFgIDAQIeAQIX
gAAKCRCuvfSBm+IYZ38/D/46eEIyG7Gb65sxt3QnlIN0+90kUjz83QpCnIyALZDc
H2wPYBCMbyJFMG+rqVE8Yoh6WF0Rqy76LG+Y/xzO9eKIJGxVcSU75ifoq/M7pI1p
aiqA9T8QcFBmo83FFoPvnid67aqg/tFsHl+YF9rUxMZndGRE9Hk96lkH1Y2wHMEs
mAa582RELVEDDD2ellOPmQr69fRPa5IdJHkXjqGtoNQy5hAp49ofMLmeQ82d2OA+
kpzgiuSw8Nh1VrMZludcUArSQDCHoXuiPG/7Wn9Vy6fvKkTQK3mCW8i5HgCa0qxe
vOKlDMz4virEEADMBs79iIyM6w1xm8JOD4734sgii2MPcQgmAlbu5LyBM5FfuO0u
rTMvZM0btSWQX3nIsxQ3far9MJvUT4nebhTo59cED+1EjkD14mReTHwtWt1aye/b
I8Rvor15RFiB8Ku6c41YmNKarSCzJDs4VEfsos4oMieEqA98J4ZOX67IT++ortcB
uXmDJgvzGWEeyVOMoc/4oDJHNQjJg9XRGy8b/J3AVhk2BE/CD4lKhX3hWGbufrQz
E8ENWuT4m3igQnBmOsrGlBPYIOKZvczQxri01vcKY95dKXb1jtnR9yR+JKgEP388
1B/8dEohynhMnzEqR9TIMEEy9Y8RKZ+Jiy+/Lg2XGrChiLsouUetfMQww6BTK+++
pw==
=tIux
-----END PGP PUBLIC KEY BLOCK-----
EOF
        mkdir -p root/etc/apt/preferences.d
        cat << 'EOF' >> root/etc/apt/preferences.d/99firefox
Package: firefox*
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 501
EOF
}

function customize() {
        store_home_on_var +root

        echo "desktop-${options[distro]}" > root/etc/hostname

        # Drop development stuff.
        exclude_paths+=(
                usr/include
                usr/{'lib*',share}/pkgconfig
                usr/lib/firmware/{'*-ucode',liquidio,mellanox,mrvl,netronome,qcom,qed}
        )

        # Support an executable VM image for quick testing.
        cat << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu
exec qemu-kvm -nodefaults \
    -machine q35 -cpu host -m 8G \
    -drive file=/usr/share/edk2/ovmf/OVMF_CODE.fd,format=raw,if=pflash,read-only=on \
    -drive file=/usr/share/edk2/ovmf/OVMF_VARS.fd,format=raw,if=pflash,snapshot=on \
    -audio pipewire,model=virtio -nic user,model=virtio-net-pci -vga virtio \
    -drive file="${IMAGE:-gpt.img}",format=raw,if=virtio,media=disk,snapshot=on \
    "$@"
EOF
}
