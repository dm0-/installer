# This is an example Gentoo build for a specific target system, the ASUS
# Chromebook Flip C100P (based on the ARM Cortex-A17 CPU).  It demonstrates
# cross-compiling for a 32-bit ARM device and generating a nonstandard kernel
# image format.  A microSD card can be formatted using the ChromeOS GPT GUIDs
# with the kernel "kernel.img" and root file system "final.img" written to the
# appropriate partitions, and it can be booted by pressing Ctrl-U on the
# startup screen while the system is in developer mode.

options+=(
        [arch]=armv7a    # Target ARM Cortex-A17 CPUs.
        [distro]=gentoo  # Use Gentoo to build this image from source.
        [bootable]=1     # Build a kernel for this system.
        [monolithic]=1   # Build all boot-related files into the kernel image.
        [networkd]=1     # Let systemd manage the network configuration.
        [squash]=1       # Use a highly compressed file system to save space.
        [uefi]=          # This platform does not support UEFI.
        [verity_sig]=1   # Require all verity root hashes to be verified.
)

packages+=(
        # Utilities
        app-arch/cpio
        app-arch/tar
        app-arch/unzip
        app-shells/bash
        dev-util/strace
        dev-vcs/git
        sys-apps/diffutils
        sys-apps/file
        sys-apps/findutils
        sys-apps/gawk
        sys-apps/grep
        sys-apps/kbd
        sys-apps/less
        sys-apps/man-pages
        sys-apps/sed
        sys-apps/which
        sys-devel/patch
        sys-process/lsof
        sys-process/procps
        ## Accounts
        app-admin/sudo
        sys-apps/shadow
        ## Hardware
        dev-libs/libgpiod
        sys-apps/usbutils
        ## Network
        net-firewall/iptables
        net-misc/openssh
        net-misc/wget
        net-wireless/wpa_supplicant
        sys-apps/iproute2

        # Disks
        net-fs/sshfs
        sys-fs/cryptsetup
        sys-fs/e2fsprogs

        # Graphics
        media-sound/pulseaudio
        x11-apps/xev
        x11-apps/xrandr
        x11-base/xorg-server
        x11-terms/xterm
        x11-wm/windowmaker
)

packages_buildroot+=(
        # The target hardware requires firmware.
        net-wireless/wireless-regdb
        sys-kernel/linux-firmware

        # Produce the signed kernel partition image in this script.
        dev-embedded/u-boot-tools
        sys-apps/dtc
        sys-boot/vboot-utils
)

function customize_buildroot() {
        local -r portage="$buildroot/usr/${options[host]}/etc/portage"

        # Tune compilation for the ARM Cortex-A17.
        $sed -i \
            -e '/^COMMON_FLAGS=/s/[" ]*$/ -march=armv7ve+simd -mtune=cortex-a17 -mfpu=neon-vfpv4 -ftree-vectorize&/' \
            "$portage/make.conf"
        echo -e 'CPU_FLAGS_ARM="edsp neon thumb thumb2 v4 v5 v6 v7 vfp vfp-d32 vfpv3 vfpv4"\nUSE="$USE neon"' >> "$portage/make.conf"

        # Use the Panfrost driver for the ARM Mali-T760 MP4 GPU.
        echo 'VIDEO_CARDS="panfrost"' >> "$portage/make.conf"

        # Enable general system settings.
        echo >> "$portage/make.conf" 'USE="$USE' \
            curl dbus elfutils gcrypt gdbm git gmp gnutls gpg http2 libnotify libxml2 mpfr nettle ncurses pcre2 readline sqlite udev uuid xml \
            bidi fribidi harfbuzz icu idn libidn2 nls truetype unicode \
            apng gif imagemagick jbig jpeg jpeg2k png svg webp xpm \
            alsa flac libsamplerate mp3 ogg pulseaudio sndfile sound speex vorbis \
            a52 aom dav1d dvd libaom mpeg theora vpx x265 \
            bzip2 gzip lz4 lzma lzo xz zlib zstd \
            acl caps cracklib fprint hardened pam seccomp smartcard xattr xcsecurity \
            acpi dri gallium kms libglvnd libkms opengl usb uvm vaapi vdpau wps \
            cairo gtk3 libdrm pango plymouth X xa xcb xft xinerama xkb xorg xrandr xvmc \
            branding ipv6 jit lto offensive threads \
            dynamic-loading hwaccel postproc startup-notification toolkit-scroll-bars user-session wide-int \
            -cups -debug -emacs -fortran -geolocation -gtk -gtk2 -introspection -llvm -oss -perl -python -sendmail -tcpd -vala'"'

        # Build less useless stuff on the host from bad dependencies.
        echo >> "$buildroot/etc/portage/make.conf" 'USE="$USE' \
            -cups -debug -emacs -fortran -gallium -geolocation -gtk -gtk2 -introspection -llvm -oss -perl -python -sendmail -tcpd -vala -X'"'

        # Disable LTO for packages broken with this architecture/ABI.
        echo 'media-libs/libvpx no-lto.conf' >> "$portage/package.env/no-lto.conf"

        # Download an NVRAM file for the wireless driver.
        script << 'EOF'
commit=ce86506f6ee3f4d1fc9e9cdc2c36645a6427c223  # Initial import in overlays.
file=/overlay-veyron/chromeos-base/chromeos-bsp-veyron/files/firmware/brcmfmac4354-sdio.txt
tmp=$(mktemp)
curl -L "https://chromium.googlesource.com/chromiumos/overlays/board-overlays/+/$commit$file?format=TEXT" > "$tmp"
test x$(sha256sum "$tmp" | sed -n '1s/ .*//p') = x24a7cdfe790e0cb067b11fd7f13205684bcd4368cfb00ee81574fe983618f906
exec base64 -d < "$tmp" > /lib/firmware/brcm/brcmfmac4354-sdio.txt
EOF

        # Install Firefox.
        fix_package firefox
        packages+=(www-client/firefox)
        echo 'EXTRA_EMAKE="OS_TEST=arm"' >> "$portage/env/cross-arm.conf"
        echo 'dev-libs/nss cross-arm.conf' >> "$portage/package.env/nss.conf"

        # Install Emacs as a terminal application.
        fix_package emacs
        packages+=(app-editors/emacs)
        echo 'app-editors/emacs -X' >> "$portage/package.use/emacs.conf"

        # Configure the kernel by only enabling this system's settings.
        write_minimal_system_kernel_configuration > "$output/config"
        enter /usr/bin/make -C /usr/src/linux allnoconfig ARCH=arm \
            CROSS_COMPILE="${options[host]}-" KCONFIG_ALLCONFIG=/wd/config V=1
}

function customize() {
        drop_debugging
        drop_development
        store_home_on_var +root

        echo chromebook > root/etc/hostname

        # Drop extra unused paths.
        exclude_paths+=(
                usr/lib/firmware
                usr/local
        )

        # Start the wireless interface if it is configured.
        mkdir -p root/usr/lib/systemd/system/network.target.wants
        ln -fns ../wpa_supplicant-nl80211@.service \
            root/usr/lib/systemd/system/network.target.wants/wpa_supplicant-nl80211@wlan0.service
}

# Override the UEFI function as a hack to produce the ChromeOS kernel partition
# image since it's basically the same stuff that goes into the UEFI executable.
function produce_uefi_exe() if opt bootable
then
        local -r dtb=/usr/src/linux/arch/arm/boot/dts/rk3288-veyron-minnie.dtb

        # Build the system's device tree blob.
        make -C /usr/src/linux -j"$(nproc)" "${dtb##*/}" \
            ARCH=arm CROSS_COMPILE="${options[host]}-" V=1

        # Build the FIT binary from the kernel and DTB.
        mkimage -f - /root/kernel.itb << EOF
/dts-v1/;
/ {
    description = "Gentoo";
    #address-cells = <1>;
    images {
        kernel@1 {
            description = "Gentoo Linux";
            data = /incbin/("/usr/src/linux/arch/arm/boot/zImage");
            type = "kernel_noload";
            arch = "arm";
            os = "linux";
            compression = "none";
            load = <0>;
            entry = <0>;
        };
        fdt@1 {
            description = "Veyron Minnie (ASUS Chromebook Flip C100P)";
            data = /incbin/("$dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
        };
    };
    configurations {
        default = "conf@1";
        conf@1 {
            description = "Gentoo Minnie";
            kernel = "kernel@1";
            fdt = "fdt@1";
        };
    };
};
EOF

        # Pack the kernel image.  Accept a custom RSA4096/SHA512 signing key.
        local b=/usr/share/vboot/devkeys/kernel.keyblock
        local p=/usr/share/vboot/devkeys/kernel_data_key.vbprivk
        if openssl x509 -noout -text < "$keydir/sign.crt" |
                sed -n '/^ *Sig.*Alg.*sha512/,${/^ *RSA Pub.*4096 bit/q0;};$q1'
        then
                dumpRSAPublicKey -cert "$keydir/sign.crt" > "$keydir/sign.keyb"
                vbutil_key --pack "$keydir/sign.vbpubk" \
                    --algorithm 8 --key "$keydir/sign.keyb" --version 1
                vbutil_key --pack "$keydir/sign.vbprivk" \
                    --algorithm 8 --key "$keydir/sign.pem" --version 1
                vbutil_keyblock --pack /root/sign.keyblock \
                    --datapubkey "$keydir/sign.vbpubk" --flags 15
                b=/root/sign.keyblock ; p="$keydir/sign.vbprivk"
        fi
        dd bs=512 count=1 if=/dev/zero of=/root/bootloader.img
        vbutil_kernel --pack kernel.img \
            --arch arm --bootloader /root/bootloader.img \
            --config kernel_args.txt --keyblock "$b" --signprivate "$p" \
            --version 1 --vmlinuz /root/kernel.itb
fi

function write_minimal_system_kernel_configuration() { $cat "$output/config.base" - << 'EOF' ; }
# Show initialization messages.
CONFIG_PRINTK=y
# Support adding swap space.
CONFIG_SWAP=y
# Support ext2/ext3/ext4 (which is not included for read-only images).
CONFIG_EXT4_FS=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_FS_SECURITY=y
CONFIG_EXT4_USE_FOR_EXT2=y
# Support encrypted partitions.
CONFIG_DM_CRYPT=m
CONFIG_DM_INTEGRITY=m
# Support FUSE.
CONFIG_FUSE_FS=m
# Support running containers in nspawn.
CONFIG_POSIX_MQUEUE=y
CONFIG_SYSVIPC=y
CONFIG_IPC_NS=y
CONFIG_NET_NS=y
CONFIG_PID_NS=y
CONFIG_USER_NS=y
CONFIG_UTS_NS=y
# Support mounting disk images.
CONFIG_BLK_DEV=y
CONFIG_BLK_DEV_LOOP=y
# Provide a fancy framebuffer console.
CONFIG_TTY=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE=y
CONFIG_DRM_FBDEV_EMULATION=y
# Build basic firewall filter options.
CONFIG_NETFILTER=y
CONFIG_NF_CONNTRACK=y
CONFIG_NETFILTER_XT_MATCH_STATE=y
CONFIG_IP_NF_IPTABLES=y
CONFIG_IP_NF_FILTER=y
CONFIG_IP6_NF_IPTABLES=y
CONFIG_IP6_NF_FILTER=y
# Support some optional systemd functionality.
CONFIG_COREDUMP=y
CONFIG_MAGIC_SYSRQ=y
CONFIG_NET_SCHED=y
CONFIG_NET_SCH_DEFAULT=y
CONFIG_NET_SCH_FQ_CODEL=y
# TARGET HARDWARE: ASUS Chromebook Flip C100P
CONFIG_AEABI=y
## Bundle firmware
CONFIG_EXTRA_FIRMWARE="brcm/brcmfmac4354-sdio.bin brcm/brcmfmac4354-sdio.txt regulatory.db regulatory.db.p7s"
## ARM Cortex-A17
CONFIG_ARCH_MULTI_V7=y
CONFIG_SMP=y
CONFIG_NR_CPUS=4
CONFIG_ARM_CPU_TOPOLOGY=y
CONFIG_VFP=y
CONFIG_VFPv3=y
CONFIG_NEON=y
CONFIG_KERNEL_MODE_NEON=y
CONFIG_ARM_ARCH_TIMER_EVTSTREAM=y
CONFIG_ARM_LPAE=y
CONFIG_ARM_PATCH_IDIV=y
CONFIG_ARM_THUMB=y
CONFIG_ARM_THUMBEE=y
CONFIG_ARM_CRYPTO=y
CONFIG_CRYPTO_SHA1_ARM_NEON=y
CONFIG_CRYPTO_SHA256_ARM=y
CONFIG_CRYPTO_SHA512_ARM=y
CONFIG_CRYPTO_AES_ARM_BS=y
## SoC RK3288
CONFIG_ARCH_ROCKCHIP=y
CONFIG_ROCKCHIP_PM_DOMAINS=y
CONFIG_ROCKCHIP_IOMMU=y
CONFIG_DRM_ROCKCHIP=y
CONFIG_ROCKCHIP_ANALOGIX_DP=y
CONFIG_I2C_RK3X=y
CONFIG_SPI=y
CONFIG_SPI_ROCKCHIP=y
CONFIG_PWM=y
CONFIG_PWM_ROCKCHIP=y
CONFIG_POWER_AVS=y
CONFIG_ROCKCHIP_IODOMAIN=y
CONFIG_RESET_CONTROLLER=y
CONFIG_ROCKCHIP_SARADC=y
CONFIG_THERMAL=y
CONFIG_ROCKCHIP_THERMAL=y
## 4GiB RAM
CONFIG_HIGHMEM=y
CONFIG_HIGHPTE=y
## ARM Mali-T760 MP4
CONFIG_DRM=y
CONFIG_DRM_PANFROST=y
## USB support
CONFIG_USB_SUPPORT=y
CONFIG_USB=y
CONFIG_USB_DEFAULT_PERSIST=y
CONFIG_USB_EHCI_HCD=y
CONFIG_USB_EHCI_HCD_PLATFORM=y
CONFIG_USB_EHCI_ROOT_HUB_TT=y
CONFIG_USB_DWC2=y
CONFIG_USB_GADGET=y
## Broadcom wireless
CONFIG_CFG80211=y
CONFIG_NETDEVICES=y
CONFIG_WLAN=y
CONFIG_WLAN_VENDOR_BROADCOM=y
CONFIG_BRCMFMAC=y
CONFIG_BRCMFMAC_SDIO=y
## ChromeOS embedded controller
CONFIG_CHROME_PLATFORMS=y
CONFIG_CROS_EC=y
CONFIG_CROS_EC_I2C=y
CONFIG_CROS_EC_SPI=y
CONFIG_I2C_CROS_EC_TUNNEL=y
## DMA
CONFIG_DMADEVICES=y
CONFIG_DMA_OF=y
CONFIG_PL330_DMA=y
## PHY
CONFIG_PHY_ROCKCHIP_DP=y
CONFIG_PHY_ROCKCHIP_USB=y
## Input
CONFIG_HID=y
CONFIG_HID_BATTERY_STRENGTH=y
CONFIG_HID_GENERIC=y
CONFIG_INPUT=y
CONFIG_INPUT_EVDEV=y
## Keyboard, touchpad, and touchscreen
CONFIG_HZ_250=y
CONFIG_INPUT_KEYBOARD=y
CONFIG_INPUT_MOUSE=y
CONFIG_INPUT_TOUCHSCREEN=y
CONFIG_KEYBOARD_CROS_EC=y
CONFIG_KEYBOARD_GPIO=y
CONFIG_MOUSE_ELAN_I2C=y
CONFIG_MOUSE_ELAN_I2C_I2C=y
CONFIG_TOUCHSCREEN_ELAN=y
## Webcam
CONFIG_MEDIA_SUPPORT=y
CONFIG_MEDIA_CAMERA_SUPPORT=y
CONFIG_MEDIA_USB_SUPPORT=y
CONFIG_USB_VIDEO_CLASS=y
CONFIG_VIDEO_DEV=y
CONFIG_VIDEO_V4L2=y
## USB storage
CONFIG_SCSI=y
CONFIG_BLK_DEV_SD=y
CONFIG_USB_STORAGE=y
CONFIG_USB_UAS=y
## Memory card, internal storage
CONFIG_MMC=y
CONFIG_MMC_BLOCK=y
CONFIG_MMC_BLOCK_MINORS=32
CONFIG_MMC_DW=y
CONFIG_MMC_DW_ROCKCHIP=y
CONFIG_MMC_SDHCI=y
CONFIG_MMC_SDHCI_PLTFM=y
CONFIG_PWRSEQ_EMMC=y
CONFIG_PWRSEQ_SIMPLE=y
## Screen
CONFIG_BACKLIGHT_CLASS_DEVICE=y
CONFIG_BACKLIGHT_PWM=y
CONFIG_DRM_PANEL_SIMPLE=y
## Battery
CONFIG_BATTERY_BQ27XXX=y
CONFIG_BATTERY_BQ27XXX_I2C=y
CONFIG_CHARGER_GPIO=y
## Clock, power, RTC
CONFIG_MFD_RK808=y
CONFIG_COMMON_CLK_RK808=y
CONFIG_REGULATOR=y
CONFIG_REGULATOR_FIXED_VOLTAGE=y
CONFIG_REGULATOR_PWM=y
CONFIG_REGULATOR_RK808=y
CONFIG_RTC_CLASS=y
CONFIG_RTC_DRV_RK808=y
## Optional USB devices
CONFIG_SND_USB=y
CONFIG_HID_GYRATION=m   # wireless mouse and keyboard
CONFIG_SND_USB_AUDIO=m  # headsets
CONFIG_USB_ACM=m        # fit-PC status LED
CONFIG_USB_HID=m        # mice and keyboards
EOF
