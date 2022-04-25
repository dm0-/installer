# SPDX-License-Identifier: GPL-3.0-or-later
local socket unitdir=root/usr/lib/systemd/system
local sockets=(
        docker
        libvirtd{,-admin,-ro}
        pcscd
        virtnetworkd{,-admin,-ro}
)
mkdir -p "$unitdir/sockets.target.wants"
for socket in "${sockets[@]}"
do
        [[ ! -s $unitdir/$socket.socket ]] ||
        ln -fst "$unitdir/sockets.target.wants" "../$socket.socket"
done
