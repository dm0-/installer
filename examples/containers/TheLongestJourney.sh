options=([arch]=i686 [distro]=fedora [nspawn]=1 [release]=30 [squash]=1)

packages+=(
        mesa-dri-drivers
        wine-core
        wine-pulseaudio
)

packages_buildroot+=(dnf-plugins-core git-core jq make)
function customize_buildroot() {
        ln 'setup_the_longest_journey_142_lang_update_(24607).exe' "$output/install.exe"
        ln 'setup_the_longest_journey_142_lang_update_(24607)-1.bin' "$output/install-1.bin"
        enter /bin/bash -euxo pipefail << 'EOF'
dnf --assumeyes builddep innoextract
git clone https://github.com/dscharrer/innoextract.git
cd innoextract
git reset --hard ce1c97441118fd1cc443847349a002c96b7640b7
cmake -DCMAKE_INSTALL_PREFIX:PATH=/usr .
make -j$(nproc) all
exec make install
EOF
}

function customize() {
        exclude_paths+=(
                root
                usr/{lib,share}/locale
                usr/lib/systemd
                usr/lib'*'/gconv
                usr/share/{doc,help,hwdata,info,licenses,man,sounds}
                var/'*'
        )

        (mkdir -p root/TLJ/Save ; cd root/TLJ ; exec innoextract ../../install.exe)
        rm -fr root/TLJ/{app,commonappdata,tmp}
        cp root/TLJ/preferences.ini root/TLJ/preferences.ini.orig
        wine_gog_script /TLJ < root/TLJ/goggame-1207658794.script > reg.sh
        sed -i -e 's/Z:/C:/g' reg.sh

        sed $'/^REG_SCRIPT/{rreg.sh\nd;}' << 'EOF' > launch.sh && chmod 0755 launch.sh
#!/bin/sh -eu

[ -e "${XDG_DATA_HOME:=$HOME/.local/share}/TheLongestJourney/Save" ] ||
mkdir -p "$XDG_DATA_HOME/TheLongestJourney/Save"

[ -e "$XDG_DATA_HOME/TheLongestJourney/preferences.ini" ] ||
touch "$XDG_DATA_HOME/TheLongestJourney/preferences.ini"

exec sudo systemd-nspawn \
    --bind="$XDG_DATA_HOME/TheLongestJourney/Save:/TLJ/Save" \
    --bind="$XDG_DATA_HOME/TheLongestJourney/preferences.ini:/TLJ/preferences.ini" \
    --bind=/dev/dri \
    --bind=/tmp/.X11-unix \
    --bind="${PULSE_SERVER:-$XDG_RUNTIME_DIR/pulse/native}:/tmp/.pulse/native" \
    --bind-ro="${PULSE_COOKIE:-$HOME/.config/pulse/cookie}:/tmp/.pulse/cookie" \
    --bind-ro=/etc/passwd \
    --chdir=/TLJ \
    --hostname=TheLongestJourney \
    --image="${IMAGE:-TheLongestJourney.img}" \
    --link-journal=no \
    --machine="TheLongestJourney-$USER" \
    --personality=x86 \
    --private-network \
    --read-only \
    --setenv="DISPLAY=$DISPLAY" \
    --setenv="HOME=/home/$USER" \
    --setenv=PULSE_COOKIE=/tmp/.pulse/cookie \
    --setenv=PULSE_SERVER=/tmp/.pulse/native \
    --tmpfs=/home \
    --user="$USER" \
    /bin/sh -euo pipefail /dev/stdin "$@" << 'END'
test -s preferences.ini || cat preferences.ini.orig > preferences.ini
(unset DISPLAY
REG_SCRIPT
)
ln -fst "$HOME/.wine/dosdevices/c:" /TLJ
exec wine explorer /desktop=virtual,640x480 /TLJ/game.exe "$@"
END
EOF
}
