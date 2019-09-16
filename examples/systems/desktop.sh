# This is a standalone workstation image that includes Firefox, VLC (supporting
# DVDs and Blu-ray discs), the GNOME desktop, some common basic utilities, and
# enough tools to build and run anything else in VMs or containers.

options+=(
        [iptables]=1  # Enable a firewall to block all inbound connections.
        [networkd]=   # Disable networkd so the desktop can use NetworkManager.
        [selinux]=1   # Enforce a targeted SELinux policy.
        [squash]=1    # Use a highly compressed file system to save space.
        [uefi]=1      # Create a UEFI executable that boots into this image.
        [verity]=1    # Prevent the file system from being modified.
)

packages+=(
        glibc-langpack-en kernel-modules{,-extra}

        # Utilities
        binutils
        emacs-nox
        file
        findutils
        git-core
        kbd
        man-{db,pages}
        strace
        tar
        unzip
        vim-minimal
        which
        ## Accounts
        passwd
        sudo
        ## Hardware
        pciutils
        usbutils
        ## Network
        bind-utils
        iproute
        net-tools
        openssh-clients
        tcpdump
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
        xorg-x11-drv-{amdgpu,intel,libinput,nouveau}

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

packages_buildroot+=(bc make gcc git-core kernel-devel)

function customize_buildroot() {
        enable_rpmfusion

        # Build a USB WiFi device's out-of-tree driver.
        enter /bin/sh -euxo pipefail << 'EOF'
git clone --branch=v5.3.4 https://github.com/aircrack-ng/rtl8812au.git
git -C rtl8812au reset --hard 2c3ce7095f446c412ac8146b88b854b6c684a03e
exec make -C rtl8812au -j"$(nproc)" all KVER="$(cd /lib/modules ; echo *)" V=1
EOF
}

function customize() {
        save_rpm_db
        store_home_on_var +root

        echo desktop > root/etc/hostname

        # Never start on Wayland, and don't show a non-GNOME application icon.
        exclude_paths+=(
                usr/share/applications/nm-connection-editor.desktop
                usr/share/wayland-sessions
                usr/share/xsessions/gnome.desktop
        )

        # Lock root, and use an unprivileged user with sudo access instead.
        sed -i -e 's/^root:[^:]*/root:*/' root/etc/shadow
        chroot root /usr/sbin/useradd -c 'Unprivileged User' -G wheel -p '' user

        # Downgrade from super-strict crypto policies for regular Internet use.
        chroot root /usr/bin/update-crypto-policies --set NEXT

        # Install the out-of-tree kernel driver.
        install -pm 0644 -t root/lib/modules/*/kernel/drivers/net/wireless rtl8812au/88XXau.ko
        depmod --basedir=root "$(cd root/lib/modules ; echo *)"
}
