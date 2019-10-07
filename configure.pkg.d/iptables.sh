if test -x root/sbin/iptables -o -h root/sbin/iptables
then
        local restore=$(test -s root/usr/lib/systemd/system/iptables-restore.service && echo -restore)

        # Map the rules from /var into /etc if needed.
        test -n "$restore" && cat << 'EOF' > root/usr/lib/tmpfiles.d/iptables.conf
d /var/lib/iptables
L /var/lib/iptables/rules-save - - - - ../../../etc/iptables
EOF

        # Write very simple IPv4 firewall rules until they are customized.
        (test -n "$restore" && cd root/etc || cd root/etc/sysconfig
                cat > iptables ; chmod 0600 iptables
        ) << 'EOF'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
COMMIT
EOF

        # Enable the services to load the rules but not to save them.
        mkdir -p root/usr/lib/systemd/system/basic.target.wants
        ln -fst root/usr/lib/systemd/system/basic.target.wants \
            ../iptables"$restore".service
fi

if test -x root/sbin/ip6tables -o -h root/sbin/ip6tables
then
        local restore=$(test -s root/usr/lib/systemd/system/ip6tables-restore.service && echo -restore)

        # Map the rules from /var into /etc if needed.
        test -n "$restore" && cat << 'EOF' > root/usr/lib/tmpfiles.d/ip6tables.conf
d /var/lib/ip6tables
L /var/lib/ip6tables/rules-save - - - - ../../../etc/ip6tables
EOF

        # Write local-only IPv6 firewall rules until they are customized.
        (test -n "$restore" && cd root/etc || cd root/etc/sysconfig
                cat > ip6tables ; chmod 0600 ip6tables
        ) << 'EOF'
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
COMMIT
EOF

        # Enable the services to load the rules but not to save them.
        mkdir -p root/usr/lib/systemd/system/basic.target.wants
        ln -fst root/usr/lib/systemd/system/basic.target.wants \
            ../ip6tables"$restore".service
fi
