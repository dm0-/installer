# SPDX-License-Identifier: GPL-3.0-or-later
if [[ -d root/usr/share/themes/Emacs/gtk-3.0 ]]
then
        [[ ! -s root/etc/gtk-3.0/settings.ini ]] &&
        mkdir -p root/etc/gtk-3.0 &&
        echo '[Settings]' > root/etc/gtk-3.0/settings.ini

        # Make the keymap match the console, and prefer dark themes.
        sed -i -e '/^.Settings]/r/dev/stdin' root/etc/gtk-3.0/settings.ini << 'EOF'
gtk-application-prefer-dark-theme = true
gtk-button-images = true
gtk-key-theme-name = Emacs
gtk-menu-images = true
EOF
fi
