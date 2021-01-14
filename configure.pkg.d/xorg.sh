# SPDX-License-Identifier: GPL-3.0-or-later
test -s root/usr/share/X11/app-defaults/XTerm &&
cat <(echo) - << 'EOF' >> root/usr/share/X11/app-defaults/XTerm
! Set some sensible defaults.
*backarrowKey: false
*cursorBlink: true
*metaSendsEscape: true
*toolBar: false
*ttyModes: erase ^?
EOF

# Default to dark mode for the XTerm-color class.
test -s root/usr/share/X11/app-defaults/XTerm-color &&
sed -i -e '/dark background/,/^$/s/^[ !]*\(.*:\)/\1/' \
    root/usr/share/X11/app-defaults/XTerm-color

# Allow passwordless users to log into the desktop through XDM.
if test -s root/etc/X11/xdm/Xresources
then
        grep -Fqs allowNullPasswd root/etc/X11/xdm/Xresources ||
        echo 'xlogin.Login.allowNullPasswd: true' >> root/etc/X11/xdm/Xresources
fi
