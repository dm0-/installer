# SPDX-License-Identifier: GPL-3.0-or-later
local name ; for name in iptables ip6tables
do
        [[ -s root/usr/lib/systemd/system/netfilter-persistent.service && ! -e root/usr/lib/systemd/system/$name.service ]] &&
        ln -fns netfilter-persistent.service "root/usr/lib/systemd/system/$name.service"
        compgen -G "root/usr/lib/systemd/system/$name*.service" || continue

        local restore=$([[ -s root/usr/lib/systemd/system/$name-restore.service ]] && echo -restore)

        # Map the rules from /var into /etc if needed.
        [[ -n $restore ]] && mkdir -p root/etc/iptables &&
        cat << EOF > root/usr/lib/tmpfiles.d/$name.conf
d /var/lib/$name
L /var/lib/$name/rules-save - - - - ../../../etc/iptables/$name.rules
EOF

        # Write very simple firewall rules until they are customized.
        (cd root/etc/iptables && name+=.rules || cd root/etc/sysconfig
                [[ -d ../../usr/share/netfilter-persistent ]] && name=rules.v$(( 0${name//[!6]} ? 6 : 4 ))
                cat > "$name" ; chmod 0600 "$name"
        ) << EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT$([[ $name == *6* ]] || echo '
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT')
COMMIT
EOF

        # Enable the services to load the rules but not to save them.
        mkdir -p root/usr/lib/systemd/system/basic.target.wants
        ln -fst root/usr/lib/systemd/system/basic.target.wants \
            "../$name$restore.service"
done
