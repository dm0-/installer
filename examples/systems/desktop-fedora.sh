# This is a standalone workstation image that includes Firefox, VLC (supporting
# DVDs and Blu-ray discs), the GNOME desktop, some common basic utilities, and
# enough tools to build and run anything else in VMs or containers.
#
# An out-of-tree driver for a USB wireless device is included to demonstrate
# setting up a build environment for bare kernel modules.  This example also
# installs the proprietary NVIDIA drivers to demonstrate how to use akmods for
# the resulting immutable image.

options+=(
        [networkd]=   # Disable networkd so the desktop can use NetworkManager.
        [selinux]=1   # Enforce a targeted SELinux policy.
        [squash]=1    # Use a highly compressed file system to save space.
        [uefi]=1      # Create a UEFI executable that boots into this image.
        [verity]=1    # Prevent the file system from being modified.
)

packages+=(
        glibc-langpack-en kernel-modules-extra

        # Utilities
        binutils
        emacs-nox
        file
        findutils
        git-core
        kbd
        lsof
        man-{db,pages}
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
        iptables-services
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
        'stix-*-fonts'

        # Browser
        firefox
        mozilla-{https-everywhere,noscript,ublock-origin}

        # VLC
        lib{aacs,bdplus,bluray-bdj}
        libdvdcss
        vlc
)

# Install packages for building bare kernel modules.
packages_buildroot+=(bc make gcc git-core kernel-devel)

function customize_buildroot() {
        enable_rpmfusion

        # Build a USB WiFi device's out-of-tree driver.
        script << 'EOF'
git clone --branch=v5.3.4 https://github.com/aircrack-ng/rtl8812au.git
git -C rtl8812au reset --hard 2c3ce7095f446c412ac8146b88b854b6c684a03e
exec make -C rtl8812au -j"$(nproc)" all KVER="$(cd /lib/modules ; compgen -G '*')" V=1
EOF

        # Build the proprietary NVIDIA drivers using akmods.
        enable_rpmfusion +nonfree
        script << 'EOF'
kernel=$(cd /lib/modules ; compgen -G '*')
echo 'blacklist nouveau' > /usr/lib/modprobe.d/nvidia.conf
dracut --force initrd.img "$kernel"  # Block nouveau in the initrd.
dnf --assumeyes install akmod-nvidia
su --login --session-command="exec akmodsbuild --kernels $kernel --verbose /usr/src/akmods/nvidia-kmod.latest" --shell=/bin/sh akmods
rpm2cpio /var/cache/akmods/kmod-nvidia-*.rpm | cpio -idD /
EOF
        packages+=(/$(cd "$buildroot" ; compgen -G 'var/cache/akmods/kmod-nvidia-*.rpm'))
}

function customize() {
        save_rpm_db
        store_home_on_var +root

        echo desktop-fedora > root/etc/hostname

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
        opt sb_key &&
        for module in \
            root/lib/modules/*/extra/nvidia/nvidia*.ko \
            root/lib/modules/*/kernel/drivers/net/wireless/88XXau.ko
        do
                /lib/modules/*/build/scripts/sign-file \
                    sha256 "$keydir/sign.key" "$keydir/sign.crt" "$module"
        done

        # Make NVIDIA use kernel mode setting and the page attribute table.
        cat << 'EOF' > root/usr/lib/modprobe.d/nvidia.conf
blacklist nouveau
options nvidia NVreg_UsePageAttributeTable=1
options nvidia-drm modeset=1
EOF
}
