# SPDX-License-Identifier: GPL-3.0-or-later
# This builds a self-executing container image of the game The Binding of Isaac
# (Wrath of the Lamb).  A single argument is required, the path to a release
# archive containing the bare SWF file.
#
# Ruffle is compiled from source to be used as the Flash player.  Persistent
# game data is saved in its own path under the calling user's XDG data
# directory to keep it isolated from the native Flash persistent store.
#
# This script implements an option to demonstrate supporting the proprietary
# NVIDIA drivers on the host system.  A numeric value selects the driver branch
# version, and a non-numeric value defaults to the latest.

options+=([distro]=fedora [gpt]=1 [release]=38 [squash]=1)

packages+=(
        alsa-plugins-pulseaudio
        gtk3
)

packages_buildroot+=(
        {alsa-lib,gtk3,openssl}-devel
        cargo
        java-latest-openjdk-headless
        tar
        unzip
)

function initialize_buildroot() {
        $cp "${1:-the_binding_of_isaac_wrath_of_the_lamb-linux-1.48-1355426233.swf.zip}" "$output/BOI.zip"

        echo tsflags=nodocs >> "$buildroot/etc/dnf/dnf.conf"
        echo '%_install_langs %{nil}' >> "$buildroot/etc/rpm/macros"

        # Download, verify, and extract a recent Ruffle source tag.
        $curl -L https://github.com/ruffle-rs/ruffle/archive/refs/tags/nightly-2023-04-18.tar.gz > "$output/ruffle.tgz"
        [[ $($sha256sum "$output/ruffle.tgz") == 135b58c657ecfb2d3474bde8f8ba4a28d08d0d5f554202f9b36587d27cc9103b\ * ]]
        $tar --transform='s,^[^/]*,ruffle,' -C "$output" -xf "$output/ruffle.tgz"
        $rm -f "$output/ruffle.tgz"

        # Support an option for running on a host with proprietary drivers.
        if opt nvidia
        then
                local -r suffix="-${options[nvidia]}xx"
                enable_repo_rpmfusion_nonfree
                packages+=("xorg-x11-drv-nvidia${suffix##-*[!0-9]*xx}-libs")
        else packages+=(mesa-vulkan-drivers)
        fi
}

function customize_buildroot() {
        local -rx RUSTFLAGS='-Copt-level=3 -Ccodegen-units=1 -Clink-arg=-Wl,-z,relro -Clink-arg=-Wl,-z,now'
        cargo build --manifest-path=ruffle/Cargo.toml --package=ruffle_desktop --release
}

function customize() {
        strip -o root/ruffle_desktop ruffle/target/release/ruffle_desktop
        unzip -p BOI.zip -x '__MACOSX/*' > root/boiwotl.swf
        rm -f BOI.zip

        cat << 'EOF' > root/init ; chmod 0755 root/init
#!/bin/sh -eu
mkdir -p "$HOME/.local/share"
ln -fns /tmp/save "$HOME/.local/share/ruffle"
exec /ruffle_desktop --fullscreen /boiwotl.swf "$@"
EOF

        sed "${options[nvidia]:+s, /dev/,&nvidia*&,}" << 'EOF' > launch.sh ; chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/TheBindingOfIsaac" ] ||
mkdir -p "$XDG_DATA_HOME/TheBindingOfIsaac"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/TheBindingOfIsaac:/tmp/save" \
    $(for dev in /dev/dri ; do echo "--bind=$dev" ; done) \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro=/etc/passwd \
    --bind-ro="/tmp/.X11-unix/X${DISPLAY##*:}" \
    --chdir="/home/$USER" \
    --hostname=TheBindingOfIsaac \
    --image="${IMAGE:-TheBindingOfIsaac.img}" \
    --link-journal=no \
    --machine="TheBindingOfIsaac-$USER" \
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
