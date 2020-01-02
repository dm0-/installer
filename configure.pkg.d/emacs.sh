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

        # If Emacs was installed, assume it is the desired default editor.
        echo 'export EDITOR=emacs' >> root/etc/skel/.bash_profile
fi
