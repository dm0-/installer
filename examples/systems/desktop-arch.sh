# SPDX-License-Identifier: GPL-3.0-or-later
# This is a standalone Arch Linux workstation image that aims to demonstrate an
# alternative to the Fedora workstation example.  It should be approximately
# equivalent so that they are interchangeable.
#
# The proprietary NVIDIA drivers are optionally installed here to demonstrate
# how to use dkms to build kernel modules for an immutable image.

options+=(
        [distro]=arch
        [gpt]=1                 # Generate a ready-to-boot full disk image.
        [squash]=1              # Use a compressed file system to save space.
        [uefi]=1                # Create a UEFI executable to boot this image.
        [verity]=1              # Prevent the file system from being modified.
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
        p7zip
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
        iptables-nft
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
        pipewire-{jack,pulse}
        wireplumber

        # Graphics
        mesa{,-vdpau} vulkan-{intel,radeon}
        xf86-video-{amdgpu,intel,nouveau}

        # Fonts
        ttf-dejavu
        ttf-liberation

        # Browser
        firefox
        firefox-{noscript,ublock-origin}

        # VLC
        lib{aacs,bluray}
        libdvdcss
        vlc
)

# Build the proprietary NVIDIA drivers using dkms.
function initialize_buildroot() if opt nvidia
then
        packages_buildroot+=(linux-hardened-headers nvidia-dkms)
        packages+=(nvidia-utils)
fi

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
        opt nvidia && (
                cd root/lib/modules/*/kernel/drivers &&
                mkdir -p ../../updates/dkms &&
                exec cp -pt ../../updates/dkms \
                   /var/lib/dkms/nvidia/*/*/*/module/nvidia*.ko.zst
        )

        # Sign the out-of-tree kernel modules to be usable with Secure Boot.
        opt nvidia && for module in root/lib/modules/*/updates/dkms/nvidia*.ko.zst
        do
                unzstd --rm "$module" ; module=${module%.zst}
                /lib/modules/*/build/scripts/sign-file \
                    sha512 "$keydir/sb.key" "$keydir/sb.crt" "$module"
        done

        # Make NVIDIA use kernel mode setting and the page attribute table.
        opt nvidia && cat << 'EOF' > root/usr/lib/modprobe.d/nvidia.conf
options nvidia NVreg_UsePageAttributeTable=1
options nvidia-drm modeset=1
softdep nvidia post: nvidia-uvm
EOF

        # Support an executable VM image for quick testing.
        cat << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu
exec qemu-kvm -nodefaults \
    -machine q35 -cpu host -m 8G -vga std -nic user,model=virtio-net-pci \
    -drive file=/usr/share/edk2/ovmf/OVMF_CODE.fd,format=raw,if=pflash,read-only=on \
    -drive file="${IMAGE:-gpt.img}",format=raw,media=disk,snapshot=on \
    -device intel-hda -device hda-output \
    "$@"
EOF
}
