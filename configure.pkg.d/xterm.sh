test -s root/usr/share/X11/app-defaults/XTerm &&
cat <(echo) - << 'EOF' >> root/usr/share/X11/app-defaults/XTerm
! Set some sensible defaults.
*backarrowKey: false
*cursorBlink: true
*metaSendsEscape: true
*toolBar: false
*ttyModes: erase ^?
EOF

test ! -s root/usr/share/X11/app-defaults/XTerm-color ||
sed -i -e '/dark background/,/^$/s/^[ !]*\(.*:\)/\1/' \
    root/usr/share/X11/app-defaults/XTerm-color
