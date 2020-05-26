# This is a standalone Arch Linux workstation image that aims to demonstrate an
# alternative to the Fedora workstation example.  It should be approximately
# equivalent so that they are interchangeable.
#
# The proprietary NVIDIA drivers are installed here to demonstrate how to use
# dkms to build kernel modules for an immutable image.

options+=(
        [distro]=arch
        [executable]=1  # Generate a VM image for fast testing.
        [networkd]=     # Disable networkd so GNOME can use NetworkManager.
        [squash]=1      # Use a highly compressed file system to save space.
        [uefi]=1        # Create a UEFI executable that boots into this image.
        [verity]=1      # Prevent the file system from being modified.
)

packages+=(
        dracut linux-{hardened,firmware}

        # Utilities
        binutils
        emacs-nox
        file
        git
        grep
        gzip
        kbd
        lsof
        man-{db,pages}
        sed
        strace
        systemd-sysvcompat
        tar
        unzip
        which
        ## Accounts
        shadow
        sudo
        ## Hardware
        pciutils
        usbutils
        ## Network
        iproute2
        iputils
        net-tools
        openssh
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
        qemu

        # GNOME
        eog
        evince
        gdm
        gnome-backgrounds
        gnome-calculator
        gnome-control-center
        gnome-clocks
        gnome-screenshot
        gnome-shell
        gnome-terminal
        gucharmap
        networkmanager

        # Graphics
        mesa{,-vdpau} vulkan-{intel,radeon}
        xf86-video-{amdgpu,intel,nouveau}

        # Fonts
        ttf-dejavu
        ttf-liberation

        # Browser
        firefox
        firefox-{extension-https-everywhere,noscript,ublock-origin}

        # VLC
        lib{aacs,bluray}
        libdvdcss
        vlc
)

# Build the proprietary NVIDIA drivers using dkms.
packages_buildroot+=(linux-hardened-headers nvidia-dkms)
packages+=(nvidia-utils)

function customize() {
        store_home_on_var +root

        echo "desktop-${options[distro]}" > root/etc/hostname

        # Drop development stuff.
        exclude_paths+=(
                usr/include
                usr/{lib,share}/pkgconfig
                'usr/lib/lib*.a'
        )

        # Install unpackaged NVIDIA drivers into the image.
        cp -pt root/lib/modules/*/kernel/drivers/video \
            /var/lib/dkms/nvidia/kernel-*/module/nvidia*.ko.xz

        # Sign the out-of-tree kernel modules to be usable with Secure Boot.
        for module in root/lib/modules/*/kernel/drivers/video/nvidia*.ko.xz
        do
                unxz "$module" ; module=${module%.xz}
                /lib/modules/*/build/scripts/sign-file \
                    sha512 "$keydir/sb.key" "$keydir/sb.crt" "$module"
        done

        # Make NVIDIA use kernel mode setting and the page attribute table.
        cat << 'EOF' > root/usr/lib/modprobe.d/nvidia.conf
blacklist nouveau
options nvidia NVreg_UsePageAttributeTable=1
options nvidia-drm modeset=1
softdep nvidia post: nvidia-uvm
EOF

        # Support an executable VM image for quick testing.
        cat << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu
exec qemu-kvm -nodefaults \
    -bios /usr/share/edk2/ovmf/OVMF_CODE.fd \
    -cpu host -m 8G -vga std -nic user \
    -drive file="${IMAGE:-disk.exe}",format=raw,media=disk \
    "$@"
EOF
}
