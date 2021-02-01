# SPDX-License-Identifier: GPL-3.0-or-later
if test -s root/etc/X11/WindowMaker/WindowMaker
then
        local -A config=(
                [CloseKey]='"Mod1+F4"'
                [CycleWorkspaces]=YES
                [DontLinkWorkspaces]=NO
                [DragMaximizedWindow]=RestoreGeometry
                [FocusMode]=sloppy
                [IconPosition]='"blv"'
                [NextWorkspaceKey]='"Mod1+Right"'
                [NoWindowOverDock]=YES
                [NoWindowOverIcons]=YES
                [OpaqueMoveResizeKeyboard]=YES
                [OpaqueResize]=YES
                [PrevWorkspaceKey]='"Mod1+Left"'
                [RunKey]='"Mod1+F2"'
                [SmoothWorkspaceBack]=YES
                [SnapToTopMaximizesFullscreen]=YES
                [WindowSnapping]=YES
                [WrapMenus]=YES
        )
        sed -i \
            -e "/[ \t]\(^$(for k in "${!config[@]}" ; do echo -n "\|$k" ; done)\) =/d" \
            -e '/^{/'r<(for k in "${!config[@]}" ; do echo "  $k = ${config[$k]};" ; done) \
            -e 's|.*/usr/share/icons|&",\n&/hicolor/scalable/apps|' \
            root/etc/X11/WindowMaker/WindowMaker
        sed -i -e 's/"Run...", /&SHORTCUT, "Mod1+F2", /' root/etc/X11/WindowMaker/WMRootMenu
fi
