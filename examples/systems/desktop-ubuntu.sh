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
        webext-ublock-origin-firefox

        # VLC
        vlc
)

# Install proprietary NVIDIA drivers.  Also update the buildroot for dracut.
function initialize_buildroot() if opt nvidia
then
        local -r driver_version=${options[nvidia]/#*[!0-9]*/525}
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

mI0ESXMwOwEEAL7UP143coSax/7/8UdgD+WjIoIxzqhkTeoGOyw/r2DlRCBPFAOH
lsUIG3AZrHcPVzA3bRTGoEYlrQ9d0+FsUI57ozHdmlsaekEJpQ2x7wZL7c1GiRqC
A4ERrC6kNJ5ruSUHhB+8qiksLWsTyjM7OjIdkmDbH/dYKdFUEKTdljKHABEBAAG0
HkxhdW5jaHBhZCBQUEEgZm9yIE1vemlsbGEgVGVhbYi2BBMBAgAgBQJJczA7AhsD
BgsJCAcDAgQVAggDBBYCAwECHgECF4AACgkQm9s9ic5J7CGfEgP/fcx3/CSAyyWL
lnL0qjjHmfpPd8MUOKB6u4HBcBNZI2q2CnuZCBNUrMUj67IzPg2llmfXC9WxuS2c
MkGu5+AXV+Xoe6pWQd5kP1UZ44boBZH9FvOLArA4nnF2hsx4GYcxVXBvCCgUqv26
qrGpaSu9kRpuTY5r6CFdjTNWtwGsPaM=
=uNvM
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
    -machine q35 -cpu host -m 8G -vga std -nic user,model=virtio-net-pci \
    -drive file=/usr/share/edk2/ovmf/OVMF_CODE.fd,format=raw,if=pflash,read-only=on \
    -drive file="${IMAGE:-gpt.img}",format=raw,if=virtio,media=disk,snapshot=on \
    -device intel-hda -device hda-output \
    "$@"
EOF
}
