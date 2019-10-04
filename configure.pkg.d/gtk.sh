if test -d root/usr/share/themes/Emacs/gtk-3.0
then
        # Make the keymap match the console, and prefer dark themes.
        mkdir -p root/etc/gtk-3.0
        cat << 'EOF' > root/etc/gtk-3.0/settings.ini
[Settings]
gtk-application-prefer-dark-theme = true
gtk-button-images = true
gtk-key-theme-name = Emacs
gtk-menu-images = true
EOF
fi
