# SPDX-License-Identifier: GPL-3.0-or-later
# Fix GNOME as best as possible.
[[ -s root/usr/share/glib-2.0/schemas/org.gnome.shell.gschema.xml ]] &&
cat << 'EOF' > root/usr/share/glib-2.0/schemas/99_fix.brain.damage.gschema.override
[org.gnome.calculator]
angle-units='radians'
button-mode='advanced'
[org.gnome.Charmap.WindowState]
maximized=true
[org.gnome.desktop.a11y]
always-show-universal-access-status=true
[org.gnome.desktop.calendar]
show-weekdate=true
[org.gnome.desktop.input-sources]
xkb-options=['compose:rwin','ctrl:nocaps','grp_led:caps']
[org.gnome.desktop.interface]
clock-format='24h'
clock-show-date=true
clock-show-seconds=true
clock-show-weekday=true
color-scheme='prefer-dark'
font-antialiasing='rgba'
font-hinting='full'
[org.gnome.desktop.media-handling]
automount=false
automount-open=false
autorun-never=true
[org.gnome.desktop.notifications]
show-in-lock-screen=false
[org.gnome.desktop.peripherals.keyboard]
numlock-state=true
[org.gnome.desktop.peripherals.touchpad]
natural-scroll=true
tap-and-drag=true
tap-to-click=true
two-finger-scrolling-enabled=true
[org.gnome.desktop.privacy]
hide-identity=true
recent-files-max-age=0
remember-app-usage=false
remember-recent-files=false
send-software-usage-stats=false
show-full-name-in-top-bar=false
[org.gnome.desktop.screensaver]
show-full-name-in-top-bar=false
user-switch-enabled=false
[org.gnome.desktop.session]
idle-delay=0
[org.gnome.desktop.wm.keybindings]
cycle-windows=['<Alt>Escape','<Alt>Tab']
cycle-windows-backward=['<Shift><Alt>Escape','<Shift><Alt>Tab']
panel-main-menu=['<Super>s','<Alt>F1','XF86LaunchA']
panel-run-dialog=['<Super>r','<Alt>F2']
show-desktop=['<Super>d']
switch-applications=['<Super>Tab']
switch-applications-backward=['<Shift><Super>Tab']
[org.gnome.desktop.wm.preferences]
button-layout='menu:minimize,maximize,close'
focus-mode='sloppy'
mouse-button-modifier='<Alt>'
visual-bell=true
[org.gnome.eog.ui]
statusbar=true
[org.gnome.Evince.Default]
continuous=false
dual-page=true
sizing-mode='fit-page'
[org.gnome.settings-daemon.plugins.media-keys]
on-screen-keyboard=['<Super>k']
[org.gnome.settings-daemon.plugins.power]
ambient-enabled=false
idle-dim=false
sleep-inactive-ac-type='nothing'
sleep-inactive-battery-type='nothing'
[org.gnome.shell]
always-show-log-out=true
favorite-apps=['firefox.desktop','vlc.desktop','gnome-terminal.desktop']
[org.gnome.shell.keybindings]
toggle-application-view=['<Super>a','XF86LaunchB']
[org.gnome.shell.overrides]
focus-change-on-pointer-rest=false
workspaces-only-on-primary=false
[org.gnome.Terminal.Legacy.Keybindings]
full-screen='disabled'
help='disabled'
[org.gnome.Terminal.Legacy.Settings]
default-show-menubar=false
menu-accelerator-enabled=false
[org.gnome.Terminal.Legacy.Profile]
background-color='#000000'
background-transparency-percent=20
foreground-color='#FFFFFF'
login-shell=true
scrollback-lines=100000
scrollback-unlimited=false
scrollbar-policy='never'
use-transparent-background=true
use-theme-colors=false
EOF

opt double_display_scale &&
[[ -s root/usr/share/glib-2.0/schemas/org.gnome.desktop.interface.gschema.xml ]] &&
cat << 'EOF' > root/usr/share/glib-2.0/schemas/99_display.scale.gschema.override
[org.gnome.desktop.interface]
scaling-factor=2
[org.gnome.settings-daemon.plugins.xsettings]
overrides={'Gdk/WindowScalingFactor':<2>}
EOF

# Rewind changes for older versions.
local -a edits=()
if [[ -s root/usr/share/gnome/gnome-version.xml ]]
then
        local -i major=$(sed -n 's,.*<platform>\([0-9]*\)</platform>.*,\1,p' root/usr/share/gnome/gnome-version.xml)
        local -i minor=$(sed -n 's,.*<minor>\([0-9]*\)</minor>.*,\1,p' root/usr/share/gnome/gnome-version.xml)
else
        edits=(0 root/usr/lib*/gnome-settings-daemon-*)
        local -i major=$([[ ${edits[-1]} =~ -[0-9]+$ ]] && echo ${edits[-1]##*-} || echo 0)
        local -i minor=0
        edits=()
fi
[[ major -gt 0 && major -le 41 ]] && edits+=(
        '/^color-scheme/d'
        '/^[[]org.gnome.settings-daemon.plugins.media-keys]/amax-screencast-length=0'
)
[[ major -eq 3 ]] && edits+=(
        's/^font-//'
        '/antialiasing/i[org.gnome.settings-daemon.plugins.xsettings]'
)
[[ major -eq 3 && minor -le 32 ]] && edits+=(
        's/desktop.peripherals.keyboard/settings-daemon.peripherals.keyboard/'
        "/^numlock-state=/s/=true/='on'/"
        '/^on-screen-keyboard=/{s/=[[]/=/;s/[],].*//;}'
)
[[ -s root/usr/share/glib-2.0/schemas/99_fix.brain.damage.gschema.override && ${#edits[@]} -gt 0 ]] &&
sed -i "${edits[@]/#/-e}" root/usr/share/glib-2.0/schemas/99_fix.brain.damage.gschema.override
