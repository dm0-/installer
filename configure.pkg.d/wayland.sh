# SPDX-License-Identifier: GPL-3.0-or-later
if [[ -x root/usr/bin/weston ]]
then
        mkdir -p root/etc/xdg/weston
        cat >> root/etc/xdg/weston/weston.ini
fi << EOF
[keyboard]
keymap_options=compose:rwin,ctrl:nocaps,grp_led:caps
numlock-on=true
[libinput]
enable-tap=true
natural-scroll=true
scroll-method=two-finger
tap-and-drag=true${options[double_display_scale]:+
[output]
scale=2}
EOF
