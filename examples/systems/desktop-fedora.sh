# This is a standalone workstation image that includes Firefox, VLC (supporting
# DVDs and Blu-ray discs), the GNOME desktop, some common basic utilities, and
# enough tools to build and run anything else in VMs or containers.
#
# An out-of-tree driver for a USB wireless device is included to demonstrate
# setting up a build environment for bare kernel modules.  This example also
# installs the proprietary NVIDIA drivers to demonstrate how to use akmods for
# the resulting immutable image.

options+=(
        [executable]=1  # Generate a VM image for fast testing.
        [networkd]=     # Disable networkd so GNOME can use NetworkManager.
        [selinux]=1     # Enforce a targeted SELinux policy.
        [squash]=1      # Use a highly compressed file system to save space.
        [uefi]=1        # Create a UEFI executable that boots into this image.
        [verity]=1      # Prevent the file system from being modified.
)

packages+=(
        glibc-langpack-en kernel-modules-extra

        # Utilities
        binutils
        bzip2
        crypto-policies-scripts
        emacs-nox
        file
        findutils
        git-core
        kbd
        lsof
        man-{db,pages}
        p7zip
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
        qemu-{audio-pa,system-x86-core,ui-curses,ui-gtk}
        systemd-container

        # Installer
        dnf{,-plugins-core}
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

        # Graphics
        mesa-{dri,omx,vdpau,vulkan}-drivers
        xorg-x11-drv-{amdgpu,intel,nouveau}

        # Fonts
        abattis-cantarell-fonts
        adobe-source-code-pro-fonts
        'dejavu-*-fonts'
        'liberation-*-fonts'
        stix-fonts

        # Browser
        firefox
        mozilla-{https-everywhere,noscript,ublock-origin}

        # VLC
        lib{aacs,bdplus}
        libdvdcss
        vlc
)

# Install the akmod package to build the proprietary NVIDIA drivers.
function initialize_buildroot() {
        enable_rpmfusion +nonfree
        $mkdir -p  "$buildroot/usr/lib/modprobe.d"
        echo 'blacklist nouveau' > "$buildroot/usr/lib/modprobe.d/nvidia.conf"
        packages_buildroot+=(akmod-nvidia)
}

# Install packages for building bare kernel modules.
packages_buildroot+=(bc make gcc git-core kernel-devel)

function customize_buildroot() {
        # Build a USB WiFi device's out-of-tree driver.
        script << 'EOF'
git clone --branch=v5.6.4.2 https://github.com/aircrack-ng/rtl8812au.git
git -C rtl8812au reset --hard 006c821ae82f0675d98db5c569a30591f5fc2a70
exec make -C rtl8812au -j"$(nproc)" all KVER="$(cd /lib/modules ; compgen -G '[0-9]*')" V=1
EOF

        # Build the proprietary NVIDIA drivers using akmods.
        script << 'EOF'
echo akmodsbuild --kernels "$(cd /lib/modules ; compgen -G '[0-9]*')" --verbose /usr/src/akmods/nvidia-kmod.latest |
su --login --session-command="exec $(</dev/stdin)" --shell=/bin/sh akmods
rpm2cpio /var/cache/akmods/kmod-nvidia-*.rpm | cpio -idD /
EOF
        packages+=(/$(cd "$buildroot" ; compgen -G 'var/cache/akmods/kmod-nvidia-*.rpm'))
}

function customize() {
        save_rpm_db +updates
        store_home_on_var +root

        echo "desktop-${options[distro]}" > root/etc/hostname

        # Never start on Wayland, and don't show a non-GNOME application icon.
        exclude_paths+=(
                usr/share/applications/nm-connection-editor.desktop
                usr/share/wayland-sessions
                usr/share/xsessions/gnome.desktop
        )

        # Downgrade from super-strict crypto policies for regular Internet use.
        chroot root /usr/bin/update-crypto-policies --set NEXT

        # Install the out-of-tree USB WiFi driver.
        install -pm 0644 -t root/lib/modules/*/kernel/drivers/net/wireless \
            rtl8812au/88XXau.ko

        # Sign the out-of-tree kernel modules to be usable with Secure Boot.
        for module in \
            root/lib/modules/*/extra/nvidia/nvidia*.ko \
            root/lib/modules/*/kernel/drivers/net/wireless/88XXau.ko
        do
                /lib/modules/*/build/scripts/sign-file \
                    sha256 "$keydir/sb.key" "$keydir/sb.crt" "$module"
        done

        # Make NVIDIA use kernel mode setting and the page attribute table.
        cat << 'EOF' > root/usr/lib/modprobe.d/nvidia.conf
blacklist nouveau
options nvidia NVreg_UsePageAttributeTable=1
options nvidia-drm modeset=1
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
