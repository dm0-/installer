# SPDX-License-Identifier: GPL-3.0-or-later
if [[ -s root/usr/share/xfwm4/defaults ]]
then
        sed -i \
            -e '/^click_to_focus=/s/=.*/=false/' \
            -e '/^focus_delay=/s/=.*/=0/' \
            root/usr/share/xfwm4/defaults

        opt double_display_scale &&
        [[ -d root/usr/share/themes/Default-xhdpi ]] &&
        sed -i -e 's/^theme=Default$/&-xhdpi/' root/usr/share/xfwm4/defaults
fi
