if local name=iptables ; test -x root/sbin/$name -o -h root/sbin/$name
then
        local restore=$(test -s root/usr/lib/systemd/system/$name-restore.service && echo -restore)

        # Map the rules from /var into /etc if needed.
        test -n "$restore" && mkdir -p root/etc/iptables &&
        cat << EOF > root/usr/lib/tmpfiles.d/$name.conf
d /var/lib/$name
L /var/lib/$name/rules-save - - - - ../../../etc/iptables/$name.rules
EOF

        # Write very simple IPv4 firewall rules until they are customized.
        (cd root/etc/iptables && name+=.rules || cd root/etc/sysconfig
                test -d ../../usr/share/netfilter-persistent && name=rules.v4
                cat > "$name" ; chmod 0600 "$name"
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
            "../$name$restore.service"
fi

if local name=ip6tables ; test -x root/sbin/$name -o -h root/sbin/$name
then
        local restore=$(test -s root/usr/lib/systemd/system/$name-restore.service && echo -restore)

        # Map the rules from /var into /etc if needed.
        test -n "$restore" && mkdir -p root/etc/iptables &&
        cat << EOF > root/usr/lib/tmpfiles.d/$name.conf
d /var/lib/$name
L /var/lib/$name/rules-save - - - - ../../../etc/iptables/$name.rules
EOF

        # Write local-only IPv6 firewall rules until they are customized.
        (cd root/etc/iptables && name+=.rules || cd root/etc/sysconfig
                test -d ../../usr/share/netfilter-persistent && name=rules.v6
                cat > "$name" ; chmod 0600 "$name"
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
            "../$name$restore.service"
fi
