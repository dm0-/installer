# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game FTL.  A single
# argument is required, the path to a Linux installer from GOG.
#
# The container includes dependencies not bundled with the game.  Persistent
# game data paths are bound into the home directory of the calling user, so the
# container is interchangeable with a native installation of the game.
#
# Since the game archive includes both i686 and x86_64 binaries, this script
# supports using either depending on whether the CLI option "-o arch=i686" was
# given.  The i686 build may not be trustworthy, however, because the distro's
# RPMs for that architecture are unsigned after Fedora 30.
#
# This script implements an option to demonstrate supporting the proprietary
# NVIDIA drivers on the host system.  A numeric value selects the driver branch
# version, and a non-numeric value defaults to the latest.

options+=([arch]=x86_64 [distro]=fedora [gpt]=1 [release]=38 [squash]=1)

packages+=(
        alsa-plugins-pulseaudio
        coreutils
        mesa-libGLU
)

packages_buildroot+=(unzip)

function initialize_buildroot() {
        $cp "${1:-ftl_advanced_edition_1_6_12_2_35269.sh}" "$output/ftl.zip"

        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        echo '%_install_langs %{nil}' >> "$buildroot/etc/rpm/macros"

        # Support an option for running on a host with proprietary drivers.
        if opt nvidia
        then
                local -r suffix="-${options[nvidia]}xx"
                enable_repo_rpmfusion_nonfree
                packages+=("xorg-x11-drv-nvidia${suffix##-*[!0-9]*xx}-libs")
        else packages+=(mesa-dri-drivers)
        fi
}

function customize_buildroot() if [[ ${options[arch]:-$DEFAULT_ARCH} == i686 ]]
then
        sed -i -e 's/^enabled=.*/enabled=0/' /etc/yum.repos.d/*.repo
        sed "${options[nvidia]:+s/^enabled=.*/enabled=1/}" << 'EOF' > /etc/yum.repos.d/koji.repo
[koji-fedora]
name=Fedora $releasever - $basearch - Packages directly from Koji
baseurl=https://kojipkgs.fedoraproject.org/repos/f$releasever-build/latest/$basearch/
enabled=1
gpgcheck=0
[koji-rpmfusion-free]
name=RPM Fusion for Fedora $releasever - Free - Packages directly from Koji
baseurl=https://koji.rpmfusion.org/kojifiles/repos/f$releasever-free-multilibs-build/latest/$basearch/
enabled=0
gpgcheck=0
[koji-rpmfusion-nonfree]
name=RPM Fusion for Fedora $releasever - Nonfree - Packages directly from Koji
baseurl=https://koji.rpmfusion.org/kojifiles/repos/f$releasever-nonfree-multilibs-build/latest/$basearch/
enabled=0
gpgcheck=0
EOF
fi

function customize() {
        exclude_paths+=(
                root
                usr/{include,lib/debug,local,src}
                usr/{lib,share}/locale
                usr/lib/{sysimage,systemd,tmpfiles.d}
                usr/lib'*'/gconv
                usr/share/{doc,help,hwdata,info,licenses,man,sounds}
        )

        local -r drop=$([[ ${options[arch]:-$DEFAULT_ARCH} == i686 ]] && echo amd64)
        unzip -Cjd root ftl.zip 'data/noarch/game/data/FTL.*' -x "*FTL.${drop:-x86}" || [[ $? -eq 1 ]]
        mv root/FTL.* root/FTL
        rm -f ftl.zip

        cat << 'EOF' > root/init ; chmod 0755 root/init
#!/bin/sh -eu
mkdir -p "$HOME/.local/share"
ln -fns /tmp/save "$HOME/.local/share/FasterThanLight"
exec /FTL "$@"
EOF

        sed "${options[nvidia]:+s, /dev/,&nvidia*&,;}${drop:+s/-64//}" << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/FasterThanLight" ] ||
mkdir -p "$XDG_DATA_HOME/FasterThanLight"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/FasterThanLight:/tmp/save" \
    $(for dev in /dev/dri ; do echo "--bind=$dev" ; done) \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro=/etc/passwd \
    --bind-ro="/tmp/.X11-unix/X${DISPLAY##*:}" \
    --chdir=/ \
    --hostname=FasterThanLight \
    --image="${IMAGE:-FasterThanLight.img}" \
    --link-journal=no \
    --machine="FasterThanLight-$USER" \
    --personality=x86-64 \
    --private-network \
    --read-only \
    --setenv="DISPLAY=$DISPLAY" \
    --setenv="HOME=/home/$USER" \
    --setenv=PULSE_COOKIE=/tmp/.pulse/cookie \
    --setenv=PULSE_SERVER=/tmp/.pulse/native \
    --tmpfs=/home \
    --user="$USER" \
    /init "$@"
EOF
}
