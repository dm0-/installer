# SPDX-License-Identifier: GPL-3.0-or-later
# This is a standalone openSUSE workstation image that aims to demonstrate an
# alternative to the Fedora workstation example.  It should be approximately
# equivalent so that they are interchangeable.
#
# The proprietary NVIDIA drivers are optionally installed here to demonstrate
# how to use the vendor's repository and install the modules in an immutable
# image without development packages.

options+=(
        [distro]=opensuse
        [gpt]=1                 # Generate a ready-to-boot full disk image.
        [selinux]=targeted      # Load this SELinux policy in permissive mode.
        [squash]=1              # Use a compressed file system to save space.
        [uefi]=1                # Create a UEFI executable to boot this image.
        [verity]=1              # Prevent the file system from being modified.
)

packages+=(
        distribution-logos-openSUSE-Tumbleweed kernel-default kernel-firmware

        # Utilities
        binutils
        bzip2
        emacs-nox
        file
        findutils
        git-core
        grep
        gzip
        kbd
        lsof
        man{,-pages}
        p7zip-full
        procps
        sed
        strace
        systemd-sysvinit
        tar
        unzip
        which
        ## Accounts
        cracklib-dict-small
        shadow
        sudo
        ## Hardware
        pciutils
        usbutils
        ## Network
        iproute2
        iptables-backend-nft
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
        squashfs
        sshfs

        # Host
        qemu-{kvm,ovmf-x86_64}
        systemd-container

        # GNOME
        adwaita-icon-theme
        bolt
        colord
        eog
        evince{,-plugin-{djvu,pdf,tiff,xps}document}
        gdm-systemd
        gjs
        gnome-backgrounds
        gnome-calculator
        gnome-control-center
        gnome-clocks
        gnome-screenshot
        gnome-shell
        gnome-terminal
        gtk3-branding-openSUSE
        gucharmap
        NetworkManager-branding-openSUSE
        pipewire{,-pulseaudio}
        upower
        wallpaper-branding-openSUSE

        # Graphics
        Mesa-{dri{,-nouveau},lib{d3d,OpenCL,va}}
        libva-vdpau-driver libvdpau_{nouveau,r{3,6}00,radeonsi}
        libvulkan_{intel,radeon}
        libXvMC_{nouveau,r600}
        xf86-{input-libinput,video-{amdgpu,intel,nouveau}}

        # Fonts
        adobe-sourcecodepro-fonts
        dejavu-fonts
        liberation-fonts
        'stix-*-fonts'

        # Browser
        MozillaFirefox MozillaFirefox-branding-openSUSE

        # VLC
        vlc-vdpau
)

# Build the proprietary NVIDIA drivers from the vendor repository.
function initialize_buildroot() if opt nvidia
then
        enable_repo_nvidia
        packages_buildroot+=(createrepo_c nvidia-gfxG05-kmp-default rpm-build)
fi

# Package the bare NVIDIA modules to satisfy bad development dependencies.
function customize_buildroot() if opt nvidia
then
        local -r name=nvidia-gfxG05-kmp
        local -r kernel=$(compgen -G '/lib/modules/*/updates/nvidia.ko' | sed -n '1s,/updates.*,,p')
        cat << EOF > "/root/$name.spec" ; rpmbuild -ba "/root/$name.spec"
Name: $name
Version: $(rpm -q --qf '%{VERSION}' "$name-default" | sed -n '1s/_.*//p')
Release: 1
Summary: Prebuilt NVIDIA modules
License: SUSE-NonFree
Conflicts: $name-default
%description
%{summary}.
%install
mkdir -p %{buildroot}%{_modprobedir} %{buildroot}$kernel
cp -at %{buildroot}%{_modprobedir} %{_modprobedir}/*nvidia*.conf
cp -at %{buildroot}$kernel $kernel/updates
%files
%{_modprobedir}/*nvidia*.conf
$kernel/updates
EOF
        createrepo_c /usr/src/packages/RPMS
        zypper addrepo --no-gpgcheck /usr/src/packages/RPMS local
        packages+=(nvidia-gfxG05-kmp nvidia-glG05 x11-video-nvidiaG05)
        # Remove the modules here to skip installing them into the initrd.
        rm -fr "$kernel/updates" ; depmod "${kernel##*/}"
fi

function customize() {
        store_home_on_var +root

        echo "desktop-${options[distro]}" > root/etc/hostname

        # Drop development stuff.
        exclude_paths+=(
                usr/include
                usr/{'lib*',share}/pkgconfig
                usr/lib/firmware/{'*-ucode',liquidio,mellanox,mrvl,netronome,qcom,qed}
        )

        # Sign the out-of-tree kernel modules to be usable with Secure Boot.
        opt nvidia && for module in root/lib/modules/*/updates/nvidia*.ko
        do
                /lib/modules/*/build/scripts/sign-file \
                    sha256 "$keydir/sb.key" "$keydir/sb.crt" "$module"
        done

        # Support an executable VM image for quick testing.
        cat << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu
exec qemu-kvm -nodefaults \
    -M q35 -cpu host -m 8G -vga std -nic user,model=virtio-net-pci \
    -drive file=/usr/share/edk2/ovmf/OVMF_CODE.fd,format=raw,if=pflash,read-only=on \
    -drive file="${IMAGE:-gpt.img}",format=raw,media=disk,snapshot=on \
    -device intel-hda -device hda-output \
    "$@"
EOF
}
