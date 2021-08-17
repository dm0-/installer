# SPDX-License-Identifier: GPL-3.0-or-later
if test -s root/etc/lxdm/lxdm.conf
then
        sed -i \
            -e 's/^[# ]*\(keyboard\|numlock\|skip_password\)=.*/\1=1/' \
            -e 's/^[# ]*\(gtk_theme\)=.*/\1=Adwaita/' \
            root/etc/lxdm/lxdm.conf

        # Select a default desktop environment.
        local wm ; for wm in startxfce4 startlxde wmaker
        do
                if test -x "root/usr/bin/$wm"
                then
                        sed -i \
                            -e "s,^[# ]*\(session\)=.*,\1=/usr/bin/$wm," \
                            root/etc/lxdm/lxdm.conf
                        break
                fi
        done
fi

opt double_display_scale &&
test -s root/usr/lib/systemd/system/lxdm.service &&
sed -i -e '/^[[]Service]$/aEnvironment=GDK_SCALE=2' root/usr/lib/systemd/system/lxdm.service
