if opt iptables
then
        local -r restore=$(test -s root/usr/lib/systemd/system/iptables-restore.service && echo -restore)

        # Map the rules from /var into /etc if needed.
        test -n "$restore" && cat << 'EOF' > root/usr/lib/tmpfiles.d/iptables.conf
d /var/lib/iptables
L /var/lib/iptables/rules-save - - - - ../../../etc/iptables
d /var/lib/ip6tables
L /var/lib/ip6tables/rules-save - - - - ../../../etc/ip6tables
EOF

        # Write very simple firewall rules in place until they are customized.
        (test -n "$restore" && cd root/etc || cd root/etc/sysconfig
                cat << 'EOF' > iptables ; chmod 0600 iptables
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
COMMIT
EOF
                cat << 'EOF' > ip6tables ; chmod 0600 ip6tables
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
COMMIT
EOF
        )

        # Enable the services to load the rules but not to save them.
        mkdir -p root/usr/lib/systemd/system/basic.target.wants
        ln -fst root/usr/lib/systemd/system/basic.target.wants \
            ../ip{,6}tables"$restore".service
fi
