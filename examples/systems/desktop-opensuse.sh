# SPDX-License-Identifier: GPL-3.0-or-later
# This is a standalone openSUSE workstation image that aims to demonstrate an
# alternative to the Fedora workstation example.  It should be approximately
# equivalent so that they are interchangeable.
#
# The proprietary NVIDIA drivers are installed here to demonstrate how to use
# the vendor's repository and install the modules in an immutable image without
# development packages.

options+=(
        [distro]=opensuse
        [gpt]=1         # Generate a VM disk image for fast testing.
        [networkd]=     # Disable networkd so GNOME can use NetworkManager.
        [selinux]=1     # Load a targeted SELinux policy in permissive mode.
        [squash]=1      # Use a highly compressed file system to save space.
        [uefi]=1        # Create a UEFI executable that boots into this image.
        [verity]=1      # Prevent the file system from being modified.
)

packages+=(
        distribution-logos-openSUSE-Tumbleweed kernel-default

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
        upower

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
function initialize_buildroot() {
        local -r repo='https://download.nvidia.com/opensuse/tumbleweed'
        $curl -L "$repo/repodata/repomd.xml.key" > "$output/nvidia.key"
        test x$($sha256sum "$output/nvidia.key" | $sed -n '1s/ .*//p') = \
            x599aa39edfa43fb81e5bf5743396137c93639ce47738f9a2ae8b9a5732c91762
        enter /usr/bin/rpmkeys --import nvidia.key
        $rm -f "$output/nvidia.key"
        echo -e > "$buildroot/etc/zypp/repos.d/nvidia.repo" \
            "[nvidia]\nenabled=1\nautorefresh=1\nbaseurl=$repo\ngpgcheck=1"
        echo 'blacklist nouveau' > "$buildroot/usr/lib/modprobe.d/nvidia.conf"
        packages_buildroot+=(nvidia-gfxG05-kmp-default)
}

# Package the bare NVIDIA modules to satisfy bad development dependencies.
packages_buildroot+=(createrepo_c rpm-build)
function customize_buildroot() {
        local -r name=nvidia-gfxG05-kmp
        local -r kernel=$(compgen -G '/lib/modules/*/updates/nvidia.ko' | sed -n '1s,/updates.*,,p')
        cat << EOF > "/root/$name.spec" ; rpmbuild -ba "/root/$name.spec"
Name: $name
Version: $(rpm -q --qf '%{VERSION}' "$name-default" | sed -n '1s/_.*//p')
Release: 1
Summary: Prebuilt NVIDIA modules
License: SUSE-NonFree
%description
%{summary}.
%install
mkdir -p %{buildroot}$kernel %{buildroot}/etc/modprobe.d
cp -at %{buildroot}$kernel $kernel/updates
cp -at %{buildroot}/etc/modprobe.d /etc/modprobe.d/50-nvidia-default.conf
%files
%config(noreplace) /etc/modprobe.d/50-nvidia-default.conf
$kernel/updates
EOF
        createrepo_c /usr/src/packages/RPMS
        zypper addrepo --no-gpgcheck /usr/src/packages/RPMS local
        packages+=(nvidia-gfxG05-kmp nvidia-glG05 x11-video-nvidiaG05)
        # Remove the modules here to skip installing them into the initrd.
        rm -fr "$kernel/updates" ; depmod "${kernel##*/}"
}

function customize() {
        store_home_on_var +root

        echo "desktop-${options[distro]}" > root/etc/hostname

        # Drop development stuff.
        exclude_paths+=(
                usr/include
                usr/{'lib*',share}/pkgconfig
        )

        # Sign the out-of-tree kernel modules to be usable with Secure Boot.
        for module in root/lib/modules/*/updates/nvidia*.ko
        do
                /lib/modules/*/build/scripts/sign-file \
                    sha256 "$keydir/sb.key" "$keydir/sb.crt" "$module"
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
    -cpu host -m 8G -vga std -soundhw hda -nic user \
    -drive file="${IMAGE:-gpt.img}",format=raw,media=disk \
    "$@"
EOF
}
