# SPDX-License-Identifier: GPL-3.0-or-later
# This is a standalone workstation image that includes Firefox, VLC (supporting
# DVDs and Blu-ray discs), the GNOME desktop, some common basic utilities, and
# enough tools to build and run anything else in VMs or containers.
#
# An out-of-tree driver for a USB wireless device is included to demonstrate
# setting up a build environment for bare kernel modules.  This example also
# optionally installs the proprietary NVIDIA drivers to demonstrate how to use
# akmods for the resulting immutable image.  A numeric option value selects the
# driver branch version, and a non-numeric value defaults to the latest.

options+=(
        [distro]=fedora
        [gpt]=1                 # Generate a ready-to-boot full disk image.
        [selinux]=targeted      # Enforce this SELinux policy.
        [squash]=1              # Use a compressed file system to save space.
        [uefi]=1                # Create a UEFI executable to boot this image.
        [verity]=1              # Prevent the file system from being modified.
)

packages+=(
        glibc-langpack-en kernel-modules-extra linux-firmware

        # Utilities
        acl
        attr
        bash-color-prompt
        binutils
        bzip2
        emacs-nox
        file
        findutils
        git-core
        kbd-legacy
        lsof
        man-{db,pages}
        p7zip
        pinentry
        strace
        tar
        unzip
        vim-minimal
        which
        ## Accounts
        cracklib-dicts
        passwd
        sudo
        ## Hardware
        pciutils
        usbutils
        ## Network
        bind-utils
        iproute
        iptables-{nft,services}
        iputils
        net-tools
        openssh-clients
        tcpdump
        traceroute
        wget

        # Disks
        cryptsetup
        dosfstools
        e2fsprogs
        fuse-sshfs
        hdparm
        lvm2
        mdadm
        squashfs-tools

        # Host
        qemu-{audio-pipewire,device-display-virtio-vga,kvm-core,ui-curses,ui-gtk}
        systemd-container

        # Installer
        dnf5-plugins
        fedora-repos-rawhide
        rpmfusion-free-release{,-rawhide,-tainted}

        # GNOME
        eog
        evince
        gnome-backgrounds
        gnome-calculator
        gnome-clocks
        gnome-screenshot
        gnome-shell
        gnome-terminal
        gucharmap
        NetworkManager-wifi
        pipewire-pulseaudio

        # Graphics
        mesa-{dri,vulkan}-drivers
        mesa-{va,vdpau}-drivers-freeworld
        xorg-x11-drv-{amdgpu,intel,nouveau}

        # Fonts
        abattis-cantarell-fonts
        adobe-source-code-pro-fonts
        default-fonts-core
        'dejavu-*-fonts'
        'liberation-*-fonts'

        # Browser
        firefox
        mozilla-{noscript,openh264,privacy-badger,ublock-origin}

        # VLC
        lib{avcodec,heif}-freeworld
        lib{aacs,bdplus}
        libdvdcss
        vlc vlc-plugin-{ffmpeg,pipewire}
        vlc-plugins-freeworld
)

# Install the akmod package to build the proprietary NVIDIA drivers.
function initialize_buildroot() if opt nvidia
then
        local -r suffix="-${options[nvidia]}xx"
        enable_repo_rpmfusion_nonfree
        $mkdir -p  "$buildroot/usr/lib/modprobe.d"
        echo 'blacklist nouveau' > "$buildroot/usr/lib/modprobe.d/nvidia.conf"
        packages_buildroot+=("akmod-nvidia${suffix##-*[!0-9]*xx}")
        packages+=(libva-nvidia-driver rpmfusion-nonfree-release{,-rawhide,-tainted})
else enable_repo_rpmfusion_free
fi

# Install packages for building bare kernel modules.
packages_buildroot+=(bc make gcc git-core kernel-devel)

function customize_buildroot() {
        # Build a USB WiFi device's out-of-tree driver.
        git clone --branch=v5.6.4.2 https://github.com/aircrack-ng/rtl8812au.git
        git -C rtl8812au reset --hard b44d288f423ede0fc7cdbf92d07a7772cd727de4
        make -C rtl8812au -j"$(nproc)" all KVER="$(cd /lib/modules ; compgen -G '[0-9]*')" V=1

        # Build the proprietary NVIDIA drivers using akmods.
        opt nvidia || return 0
        echo exec akmodsbuild \
            --kernels "$(cd /lib/modules ; compgen -G '[0-9]*')" \
            --verbose /usr/src/akmods/nvidia*-kmod.latest |
        su --login --session-command="$(</dev/stdin)" --shell=/bin/sh akmods
        rpm2cpio /var/cache/akmods/kmod-nvidia-*.rpm | cpio -idD /
        packages+=(/var/cache/akmods/kmod-nvidia-*.rpm)
}

function customize() {
        check_for_updates
        store_home_on_var +root

        echo "desktop-${options[distro]}" > root/etc/hostname

        # Downgrade from super-strict crypto policies for regular Internet use.
        base_dir=$PWD/root/etc/crypto-policies \
        profile_dir=$PWD/root/usr/share/crypto-policies \
        update-crypto-policies --no-reload --set NEXT

        # Install the out-of-tree USB WiFi driver.
        install -pm 0644 -t root/lib/modules/*/kernel/drivers/net/wireless \
            rtl8812au/88XXau.ko

        # Sign the out-of-tree kernel modules to be usable with Secure Boot.
        for module in \
            ${options[nvidia]:+root/lib/modules/*/extra/nvidia*/*.ko.xz} \
            root/lib/modules/*/kernel/drivers/net/wireless/88XXau.ko
        do
                [[ $module == *.xz ]] && unxz "$module" ; module=${module%.xz}
                /lib/modules/*/build/scripts/sign-file \
                    sha256 "$keydir/sb.key" "$keydir/sb.crt" "$module"
        done

        # Make NVIDIA use kernel mode setting and the page attribute table.
        opt nvidia && cat << 'EOF' > root/usr/lib/modprobe.d/nvidia.conf
blacklist nouveau
options nvidia NVreg_UsePageAttributeTable=1
options nvidia-drm modeset=1
EOF

        # Support an executable VM image for quick testing.
        cat << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu
exec qemu-kvm -nodefaults \
    -machine q35 -cpu host -m 8G \
    -drive file=/usr/share/edk2/ovmf/OVMF_CODE.fd,format=raw,if=pflash,read-only=on \
    -drive file=/usr/share/edk2/ovmf/OVMF_VARS.fd,format=raw,if=pflash,snapshot=on \
    -audio pipewire,model=virtio -nic user,model=virtio-net-pci -vga virtio \
    -drive file="${IMAGE:-gpt.img}",format=raw,media=disk,snapshot=on \
    "$@"
EOF
}
