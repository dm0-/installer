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
        gnome-backgrounds
        gnome-calculator
        gnome-clocks
        gnome-control-center
        gnome-screenshot
        gnome-session
        gnome-terminal
        gucharmap
        network-manager-gnome
        pipewire-{media-session,pulse}

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
        local -r driver_version=${options[nvidia]/#*[!0-9]*/495}
        packages+=(
                "linux-modules-nvidia-$driver_version-generic"
                "xserver-xorg-video-nvidia-$driver_version"
        )
        packages_buildroot+=("linux-modules-nvidia-$driver_version-generic")
fi

function customize() {
        store_home_on_var +root

        echo "desktop-${options[distro]}" > root/etc/hostname

        # Drop development stuff.
        exclude_paths+=(
                usr/include
                usr/{'lib*',share}/pkgconfig
                usr/lib/firmware/{netronome,'*-ucode'}
        )

        # Support an executable VM image for quick testing.
        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu
exec qemu-kvm -nodefaults \
    -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \
    -cpu host -m 8G -vga std -nic user \
    -drive file="${IMAGE:-gpt.img}",format=raw,media=disk,snapshot=on \
    -device intel-hda -device hda-output \
    "$@"
EOF
}
