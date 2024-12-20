# SPDX-License-Identifier: GPL-3.0-or-later
# Reject empty passwords and root logins.
[[ -s root/etc/ssh/sshd_config ]] &&
sed -i \
    -e 's/^[# ]*\(PermitEmptyPasswords\|PermitRootLogin\) .*/\1 no/' \
    root/etc/ssh/sshd_config

# If the SSH server is installed, enable it by default.
if [[ -s root/usr/lib/systemd/system/sshd.service ]]
then
        mkdir -p root/usr/lib/systemd/system/multi-user.target.wants
        ln -fst root/usr/lib/systemd/system/multi-user.target.wants \
            ../sshd.service
fi
