# SPDX-License-Identifier: GPL-3.0-or-later
# This is an example Gentoo build for a specific target system, the ASUS
# Chromebook Flip C100P (based on the ARM Cortex-A17 CPU).  It demonstrates
# cross-compiling for a 32-bit ARMv7-A device and generating a ChromeOS kernel
# partition image.
#
# The GPT image is modified from the usual UEFI layout to produce an image with
# a prioritized ChromeOS kernel partition and its root file system.  When the
# image is booted, it will automatically repartition the disk to have two
# ChromeOS kernel partitions, two root file system partitions, and a persistent
# /var partition.  At least a 4GiB microSD card should be used for this.
#
# After writing gpt.img to a microSD card, it can be booted by pressing Ctrl-U
# on the startup screen while the system is in developer mode.

options+=(
        [arch]=armv7a    # Target ARM Cortex-A17 CPUs.
        [distro]=gentoo  # Use Gentoo to build this image from source.
        [bootable]=1     # Build a kernel for this system.
        [gpt]=1          # Generate a ready-to-boot GPT disk image.
        [monolithic]=1   # Build all boot-related files into the kernel image.
        [networkd]=1     # Let systemd manage the network configuration.
        [uefi]=          # This platform does not support UEFI.
        [verity_sig]=1   # Require all verity root hashes to be verified.
)

packages+=(
        # Utilities
        app-arch/cpio
        app-arch/tar
        app-arch/unzip
        app-editors/emacs
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
        lxde-base/lxdm
        media-sound/pavucontrol
        media-video/pipewire
        x11-apps/xev
        x11-base/xorg-server
        xfce-base/xfce4-meta

        # Browser
        www-client/firefox
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

function initialize_buildroot() {
        local -r portage="$buildroot/usr/${options[host]}/etc/portage"

        # Tune compilation for the ARM Cortex-A17.
        $sed -i \
            -e '/^COMMON_FLAGS=/s/[" ]*$/ -mcpu=cortex-a17 -mfpu=neon-vfpv4 -ftree-vectorize&/' \
            "$portage/make.conf"
        $cat << 'EOF' >> "$portage/make.conf"
CPU_FLAGS_ARM="edsp neon thumb thumb2 v4 v5 v6 v7 vfp vfp-d32 vfpv3 vfpv4"
RUST_TARGET="thumbv7neon-unknown-linux-gnueabihf"
RUSTFLAGS="-C target-cpu=cortex-a17"
EOF
        echo >> "$buildroot/etc/portage/env/rust-map.conf" \
            "RUST_CROSS_TARGETS=\"$(archmap_llvm ${options[arch]}):thumbv7neon-unknown-linux-gnueabihf:${options[host]}\""

        # Use the Panfrost driver for the ARM Mali-T760 MP4 GPU.
        echo 'VIDEO_CARDS="panfrost"' >> "$portage/make.conf"

        # Enable general system settings.
        echo >> "$portage/make.conf" 'USE="$USE' \
            berkdb dbus elfutils emacs gdbm git glib json libnotify libxml2 magic ncurses pcre2 readline sqlite udev uuid xml \
            bidi fontconfig fribidi harfbuzz icu idn libidn2 nls truetype unicode \
            apng exif gif imagemagick jbig jpeg jpeg2k png svg tiff webp xpm \
            a52 alsa cdda faad flac libcanberra libsamplerate mp3 ogg opus pulseaudio sndfile sound speex vorbis \
            aacs aom bdplus bluray cdio dav1d dvd ffmpeg libaom mpeg theora vpx x265 \
            brotli bzip2 gzip lz4 lzma lzo snappy xz zlib zstd \
            cryptsetup gcrypt gmp gnutls gpg mpfr nettle \
            curl http2 ipv6 libproxy modemmanager networkmanager wifi wps \
            acl caps cracklib fprint hardened pam policykit seccomp smartcard xattr xcsecurity \
            acpi dri gallium gusb kms libglvnd libkms opengl upower usb uvm vaapi vdpau \
            cairo colord gtk gtk3 gui lcms libdrm pango uxa wnck X xa xcb xft xinerama xkb xorg xrandr xvmc xwidgets \
            aio branding haptic jit lto offensive pcap realtime system-info threads udisks utempter vte \
            dynamic-loading gzip-el hwaccel postproc repart startup-notification toolkit-scroll-bars user-session wide-int \
            -cups -dbusmenu -debug -geolocation -gstreamer -llvm -oss -perl -python -sendmail -tcpd \
            -gui -networkmanager -wifi'"'

        # Pass FPU flags through LDFLAGS so this package works with LTO.
        echo "LDFLAGS=\"\${LDFLAGS} $($sed -n 's/^COMMON_FLAGS=.* \(-mfpu=[^" ]*\).*/\1/p' "$portage/make.conf")\"" >> "$portage/env/ldflags-fpu.conf"
        echo 'media-libs/libvpx ldflags-fpu.conf' >> "$portage/package.env/fix-cross-compiling.conf"

        # Disable LTO for packages broken with this architecture/ABI.
        echo 'www-client/firefox -lto' >> "$portage/package.use/firefox.conf"
}

function customize_buildroot() {
        # Build less useless stuff on the host from bad dependencies.
        echo >> /etc/portage/make.conf 'USE="$USE' \
            -cups -debug -emacs -geolocation -gstreamer -llvm -oss -perl -python -sendmail -tcpd -X'"'

        # Download an NVRAM file for the wireless driver.
        local -r commit=ce86506f6ee3f4d1fc9e9cdc2c36645a6427c223  # Initial import in overlays.
        local -r file=/overlay-veyron/chromeos-base/chromeos-bsp-veyron/files/firmware/brcmfmac4354-sdio.txt
        curl -L "https://chromium.googlesource.com/chromiumos/overlays/board-overlays/+/$commit$file?format=TEXT" > /root/nvram.txt
        test x$(sha256sum /root/nvram.txt | sed -n '1s/ .*//p') = x24a7cdfe790e0cb067b11fd7f13205684bcd4368cfb00ee81574fe983618f906
        base64 -d < /root/nvram.txt > "/lib/firmware/brcm/${file##*/}"

        # Configure the kernel by only enabling this system's settings.
        write_system_kernel_config
}

function customize() {
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

        # Use a persistent /var partition with bare ext4.
        echo >> root/etc/fstab \
            "PARTUUID=${options[var_uuid]:=$(</proc/sys/kernel/random/uuid)}" /var ext4 \
            defaults,nodev,nosuid,x-systemd.growfs,x-systemd.makefs,x-systemd.rw-only 1 2

        # Define a default partition layout: two kernels, two roots, and var.
        mkdir -p root/usr/lib/repart.d
        opt esp_size || options[esp_size]=$(( 16 << 20 ))
        cat << EOF > root/usr/lib/repart.d/15-kern-a.conf
[Partition]
Label=KERN-A
SizeMaxBytes=${options[esp_size]}
SizeMinBytes=${options[esp_size]}
Type=FE3A2A5D-4F32-41A7-B725-ACCC3285A309
EOF
        cat << EOF > root/usr/lib/repart.d/20-root-a.conf
[Partition]
Label=ROOT-A
SizeMaxBytes=$(( 0${options[squash]:+1} ? 1 << 30 : 3 << 29 ))
SizeMinBytes=$(( 0${options[squash]:+1} ? 1 << 30 : 3 << 29 ))
Type=0FC63DAF-8483-4772-8E79-3D69D8477DE4
EOF
        sed s/KERN-A/KERN-B/ root/usr/lib/repart.d/15-kern-a.conf \
            > root/usr/lib/repart.d/25-kern-b.conf
        sed s/ROOT-A/ROOT-B/ root/usr/lib/repart.d/20-root-a.conf \
            > root/usr/lib/repart.d/30-root-b.conf
        cat << EOF > root/usr/lib/repart.d/50-var.conf
[Partition]
FactoryReset=on
Label=var
SizeMinBytes=$(( 512 << 20 ))
Type=var
UUID=${options[var_uuid]}
EOF
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
        tee /root/kernel.its << EOF | mkimage -f - /root/kernel.itb
/dts-v1/;
/ {
    description = "Gentoo";
    #address-cells = <1>;
    images {
        kernel-1 {
            description = "Gentoo Linux";
            data = /incbin/("/usr/src/linux/arch/arm/boot/zImage");
            type = "kernel_noload";
            arch = "arm";
            os = "linux";
            compression = "none";
            load = <0>;
            entry = <0>;
        };
        fdt-1 {
            description = "Veyron Minnie (ASUS Chromebook Flip C100P)";
            data = /incbin/("$dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
        };
    };
    configurations {
        default = "conf-1";
        conf-1 {
            description = "Gentoo Minnie";
            kernel = "kernel-1";
            fdt = "fdt-1";
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

# Override image partitioning to replace the ESP with a ChromeOS kernel.
declare -f verify_distro &>/dev/null &&
eval "$(declare -f partition | $sed '
s/BOOT.*.EFI\|esp.img/kernel.img/g;/272629760/d;s/4194304 *+ *//
s/uefi/bootable/g;/^ *if opt bootab/,/^ *fi/{/dd/!d;s/dd/opt bootable \&\& &/;}
s/C12A7328-F81F-11D2-BA4B-00A0C93EC93B/FE3A2A5D-4F32-41A7-B725-ACCC3285A309/g
s/size=[^ ,]*esp[^ ,]*,/'\''attrs="50 51 52 54 56"'\'', &/g
s/"EFI System Partition"/KERN-A/g')"

function write_system_kernel_config() if opt bootable
then cat >> /etc/kernel/config.d/system.config
fi << 'EOF'
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
CONFIG_BLK_DEV_DM=y
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
# Support basic nftables firewall options.
CONFIG_NETFILTER=y
CONFIG_NF_CONNTRACK=y
CONFIG_NF_TABLES=y
CONFIG_NF_TABLES_IPV4=y
CONFIG_NF_TABLES_IPV6=y
CONFIG_NFT_COUNTER=y
CONFIG_NFT_CT=y
## Support translating iptables to nftables.
CONFIG_NFT_COMPAT=y
CONFIG_NETFILTER_XTABLES=y
CONFIG_NETFILTER_XT_MATCH_STATE=y
# Support some optional systemd functionality.
CONFIG_COREDUMP=y
CONFIG_MAGIC_SYSRQ=y
CONFIG_NET_SCHED=y
CONFIG_NET_SCH_DEFAULT=y
CONFIG_NET_SCH_FQ_CODEL=y
# TARGET HARDWARE: ASUS Chromebook Flip C100P
CONFIG_AEABI=y
## Bundle firmware
CONFIG_EXTRA_FIRMWARE="brcm/brcmfmac4354-sdio.bin brcm/brcmfmac4354-sdio.clm_blob brcm/brcmfmac4354-sdio.txt regulatory.db regulatory.db.p7s"
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
## Maxim MAX98090 audio
CONFIG_SOUND=y
CONFIG_SND=y
CONFIG_SND_SOC=y
CONFIG_SND_SOC_ROCKCHIP=y
CONFIG_SND_SOC_ROCKCHIP_MAX98090=y
CONFIG_ROCKCHIP_DW_HDMI=y
CONFIG_DRM_DW_HDMI_I2S_AUDIO=y
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
## GPIO
CONFIG_GPIO_CDEV=y
CONFIG_GPIO_CDEV_V1=y
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
## Clock
CONFIG_COMMON_CLK_ROCKCHIP=y
CONFIG_CLK_RK3288=y
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
