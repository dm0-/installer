# SPDX-License-Identifier: GPL-3.0-or-later
if test -x root/usr/bin/emacs -o -h root/usr/bin/emacs
then
        # Enable some basics to make Emacs more useful and less annoying.
        cat << 'EOF' > root/etc/skel/.emacs
; Enable the Emacs package manager.
(require 'package)
(add-to-list 'package-archives '("melpa" . "http://melpa.org/packages/") t)
(package-initialize)
; Efficiency
(menu-bar-mode 0)
(fset 'yes-or-no-p 'y-or-n-p)
(setq gc-cons-threshold 10485760)
(setq kill-read-only-ok t)
; Cleanliness
(setq-default indent-tabs-mode nil)
(setq backup-inhibited t)
(setq auto-save-default nil)
; Time
(setq display-time-day-and-date t)
(setq display-time-24hr-format t)
(display-time-mode 1)
; Place
(setq line-number-mode t)
(setq column-number-mode t)
(when (and (version<= "26.0.50" emacs-version) (<= 100 (window-total-width)))
 (global-display-line-numbers-mode))
EOF

        # Generate the portable dump file on boot if it wasn't packaged.
        compgen -G "root/usr/libexec/emacs/2[7-9].*/*/" &&  # Only Emacs >= 27
        if ! compgen -G "root/usr/libexec/emacs/*/*/emacs*.pdmp"
        then
                ln -fst root/usr/libexec/emacs/*/* \
                    ../../../../../var/cache/emacs/emacs.pdmp
                mkdir -p root/usr/lib/systemd/system/multi-user.target.wants
                cat << 'EOF' > root/usr/lib/systemd/system/emacs-pdmp.service
[Unit]
Description=Create a cached portable dump file for faster Emacs startup
ConditionPathExists=!/var/cache/emacs/emacs.pdmp
[Service]
CacheDirectory=emacs
ExecStart=/usr/bin/emacs --batch --eval='(dump-emacs-portable "/var/cache/emacs/emacs.pdmp")'
Type=oneshot
[Install]
WantedBy=multi-user.target
EOF
                ln -fst root/usr/lib/systemd/system/multi-user.target.wants \
                    ../emacs-pdmp.service
        fi

        # If Emacs was installed, assume it is the desired default editor.
        echo 'export EDITOR=emacs' >> root/etc/skel/.bash_profile
fi
