# This is an example Gentoo build for a specific target system, the fit-PC Slim
# (based on the AMD Geode LX 800 CPU).  It demonstrates cross-compiling to an
# uncommon instruction set with plenty of other hardware components that are
# specific to that platform.  Sample bootloader files are prepared that allow
# booting this system from a GPT/UEFI-formatted disk.

options+=(
        [arch]=i686      # Target AMD Geode LX CPUs.  (Note i686 has no NOPL.)
        [distro]=gentoo  # Use Gentoo to build this image from source.
        [bootable]=1     # Build a kernel for this system.
        [monolithic]=1   # Build all boot-related files into the kernel image.
        [networkd]=1     # Let systemd manage the network configuration.
        [squash]=1       # Compress the image while experimenting.
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
        sys-apps/pciutils
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
)

# Build unused GRUB images for this platform for separate manual installation.
function initialize_buildroot() {
        echo 'GRUB_PLATFORMS="pc"' >> "$buildroot/etc/portage/make.conf"
        packages_buildroot+=(sys-boot/grub)
}

function customize_buildroot() {
        local -r portage="$buildroot/usr/${options[host]}/etc/portage"

        # Tune compilation for the AMD Geode LX 800.
        $sed -i \
            -e '/^COMMON_FLAGS=/s/[" ]*$/ -march=geode -mmmx -m3dnow -ftree-vectorize&/' \
            "$portage/make.conf"
        echo 'CPU_FLAGS_X86="3dnow 3dnowext mmx mmxext"' >> "$portage/make.conf"
        echo 'ABI_X86="32 64"' >> "$buildroot/etc/portage/make.conf"  # Portage is bad.

        # Use the Geode video driver.
        echo -e 'USE="$USE ztv"\nVIDEO_CARDS="geode"' >> "$portage/make.conf"

        # Enable general system settings.
        echo >> "$portage/make.conf" 'USE="$USE' \
            curl dbus elfutils gcrypt gdbm git gmp gnutls gpg libnotify libxml2 mpfr nettle ncurses pcre2 readline sqlite udev uuid xml \
            bidi fribidi harfbuzz icu idn libidn2 nls truetype unicode \
            apng gif imagemagick jbig jpeg jpeg2k png svg webp xpm \
            alsa flac libsamplerate mp3 ogg pulseaudio sndfile sound speex vorbis \
            a52 aom dvd libaom mpeg theora vpx x265 \
            bzip2 gzip lz4 lzma lzo xz zlib zstd \
            acl caps cracklib fprint hardened pam seccomp smartcard xattr xcsecurity \
            acpi dri gallium kms libglvnd libkms opengl usb uvm vaapi vdpau wps \
            cairo gtk3 libdrm pango plymouth X xa xcb xft xinerama xkb xorg xrandr xvmc \
            branding ipv6 jit lto offensive threads \
            dynamic-loading hwaccel postproc startup-notification toolkit-scroll-bars user-session wide-int \
            -cups -debug -emacs -fortran -gallium -geolocation -gtk -gtk2 -introspection -llvm -oss -perl -python -sendmail -tcpd -vala'"'

        # Build less useless stuff on the host from bad dependencies.
        echo >> "$buildroot/etc/portage/make.conf" 'USE="$USE' \
            -cups -debug -emacs -fortran -gallium -geolocation -gtk -gtk2 -introspection -llvm -oss -perl -python -sendmail -tcpd -vala -X'"'

        # Install Firefox, patched to drop its SSE requirement.
        fix_package firefox
        packages+=(www-client/firefox)
        echo >> "$buildroot/etc/portage/env/rust-map.conf" \
            "RUST_CROSS_TARGETS=\"$(archmap_llvm i586):$(archmap_rust i586):${options[host]}\""
        echo 'www-client/firefox -lto' >> "$portage/package.use/firefox.conf"
        firefox_patch > "$portage/patches/www-client/firefox/i586.patch"

        # Install Emacs as a terminal application.
        fix_package emacs
        packages+=(app-editors/emacs)
        echo 'app-editors/emacs -X' >> "$portage/package.use/emacs.conf"

        # Configure the kernel by only enabling this system's settings.
        write_minimal_system_kernel_configuration > "$output/config"
        enter /usr/bin/make -C /usr/src/linux allnoconfig ARCH=x86 \
            CROSS_COMPILE="${options[host]}-" KCONFIG_ALLCONFIG=/wd/config V=1
}

function customize() {
        drop_debugging
        drop_development
        store_home_on_var +root

        echo fitpc > root/etc/hostname

        # Drop extra unused paths.
        exclude_paths+=(
                usr/lib/firmware
                usr/local
        )

        # Start the wireless interface if it is configured.
        mkdir -p root/usr/lib/systemd/system/network.target.wants
        ln -fns ../wpa_supplicant-nl80211@.service \
            root/usr/lib/systemd/system/network.target.wants/wpa_supplicant-nl80211@wlp0s15f5u4.service

        # Include a mount point for a writable boot partition.
        mkdir root/boot

        create_gpt_bios_grub_files
}

# Make our own BIOS GRUB files for booting from a GPT disk.  Formatting a disk
# with fdisk forces the first partition to begin at least 1MiB from the start
# of the disk, which is the usual size of the boot partition that GRUB requires
# to install on GPT.  Reconfigure GRUB's boot.img and diskboot.img so the core
# image can be booted when written directly after the GPT.
#
# Install these files with the following commands:
#       dd bs=512 conv=notrunc if=core.img of="$disk" seek=34
#       dd bs=512 conv=notrunc if=boot.img of="$disk"
function create_gpt_bios_grub_files() if opt bootable
then
        # Take the normal boot.img, and make it a protective MBR.
        cp -pt . /usr/lib/grub/i386-pc/boot.img
        dd bs=1 conv=notrunc count=64 of=boot.img seek=446 \
            if=<(echo -en '\0\0\x02\0\xEE\xFF\xFF\xFF\x01\0\0\0\xFF\xFF\xFF\xFF' ; exec cat /dev/zero)

        # Create a core.img with preloaded modules to read /grub.cfg on an ESP.
        grub-mkimage \
            --compression=none \
            --format=i386-pc \
            --output=core.img \
            --prefix='(hd0,gpt1)' \
            biosdisk fat halt linux loadenv minicmd normal part_gpt reboot test

        # Set boot.img and diskboot.img to load immediately after the GPT.
        dd bs=1 conv=notrunc count=1 if=<(echo -en '\x22') of=boot.img seek=92
        dd bs=1 conv=notrunc count=1 if=<(echo -en '\x23') of=core.img seek=500
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
# Support VFAT (which is not included when not using UEFI).
CONFIG_VFAT_FS=m
CONFIG_FAT_DEFAULT_UTF8=y
CONFIG_NLS=m
CONFIG_NLS_DEFAULT="utf8"
CONFIG_NLS_CODEPAGE_437=m
CONFIG_NLS_ISO8859_1=m
CONFIG_NLS_UTF8=m
# Support mirroring disks via RAID.
CONFIG_MD=y
CONFIG_BLK_DEV_MD=y
CONFIG_MD_AUTODETECT=y
CONFIG_MD_RAID1=y
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
CONFIG_FB=y
CONFIG_TTY=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_VGA_CONSOLE=y
CONFIG_FRAMEBUFFER_CONSOLE=y
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
# TARGET HARDWARE: fit-PC Slim
CONFIG_PCI=y
CONFIG_PCI_MSI=y
CONFIG_SCx200=y
## Bundle firmware
CONFIG_EXTRA_FIRMWARE="regulatory.db regulatory.db.p7s rt73.bin"
## Geode LX 800 CPU
CONFIG_MGEODE_LX=y
CONFIG_CPU_SUP_AMD=y
CONFIG_MICROCODE_AMD=y
## AES processor
CONFIG_CRYPTO_HW=y
CONFIG_CRYPTO_DEV_GEODE=y
## Random number generator
CONFIG_HW_RANDOM=y
CONFIG_HW_RANDOM_GEODE=y
## Disks
CONFIG_ATA=y
CONFIG_ATA_SFF=y
CONFIG_ATA_BMDMA=y
CONFIG_PATA_CS5536=y
#CONFIG_BLK_DEV_CS5536=y  # Legacy IDE version
## Graphics
CONFIG_FB_GEODE=y
CONFIG_FB_GEODE_LX=y
CONFIG_DEVMEM=y           # Required by the X video driver
CONFIG_X86_IOPL_IOPERM=y  # Required by the X video driver
CONFIG_X86_MSR=y          # Required by the X video driver
## Audio
CONFIG_SOUND=y
CONFIG_SND=y
CONFIG_SND_PCI=y
CONFIG_SND_CS5535AUDIO=y
## USB support
CONFIG_USB_SUPPORT=y
CONFIG_USB=y
CONFIG_USB_DEFAULT_PERSIST=y
CONFIG_USB_PCI=y
CONFIG_USB_GADGET=y
CONFIG_USB_AMD5536UDC=y
# Serial support
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_RUNTIME_UARTS=2
## Ethernet
CONFIG_NETDEVICES=y
CONFIG_ETHERNET=y
CONFIG_NET_VENDOR_REALTEK=y
CONFIG_8139TOO=y
## Wifi
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_MAC80211_RC_MINSTREL=y
CONFIG_WLAN=y
CONFIG_WLAN_VENDOR_RALINK=y
CONFIG_RT2X00=y
CONFIG_RT73USB=y
## High-resolution timers
CONFIG_MFD_CS5535=y
CONFIG_CS5535_MFGPT=y
CONFIG_CS5535_CLOCK_EVENT_SRC=y
## Watchdog device
CONFIG_WATCHDOG=y
CONFIG_GEODE_WDT=y
## GPIO
CONFIG_GPIOLIB=y
CONFIG_GPIO_CS5535=y
## NAND controller
CONFIG_MTD=y
CONFIG_MTD_RAW_NAND=y
CONFIG_MTD_NAND_CS553X=y
## I2C
CONFIG_I2C=y
CONFIG_SCx200_ACB=y
## Input
CONFIG_HID=y
CONFIG_HID_BATTERY_STRENGTH=y
CONFIG_HID_GENERIC=y
CONFIG_INPUT=y
CONFIG_INPUT_EVDEV=y
## USB storage
CONFIG_USB_OHCI_HCD=y
CONFIG_USB_OHCI_HCD_PCI=y
CONFIG_USB_EHCI_HCD=y
CONFIG_USB_EHCI_HCD_PCI=y
CONFIG_SCSI=y
CONFIG_BLK_DEV_SD=y
CONFIG_USB_STORAGE=y
CONFIG_USB_UAS=y
## Optional USB devices
CONFIG_SND_USB=y
CONFIG_HID_GYRATION=m   # wireless mouse and keyboard
CONFIG_SND_USB_AUDIO=m  # headsets
CONFIG_USB_ACM=m        # fit-PC status LED
CONFIG_USB_HID=m        # mice and keyboards
EOF

function firefox_patch() { $cat << 'EOF' ; }
--- a/build/moz.configure/init.configure
+++ b/build/moz.configure/init.configure
@@ -1066,7 +1066,7 @@
     return namespace(
         OS_TARGET=os_target,
         OS_ARCH=os_arch,
-        INTEL_ARCHITECTURE=target.cpu in ('x86', 'x86_64') or None,
+        INTEL_ARCHITECTURE=None,
     )
 
 
--- a/build/moz.configure/rust.configure
+++ b/build/moz.configure/rust.configure
@@ -252,6 +252,7 @@
             (host_or_target.cpu, host_or_target.endianness, host_or_target.os), [])
 
         def find_candidate(candidates):
+            if len([c for c in candidates if c.rust_target == 'i586-unknown-linux-gnu']) >= 1: return 'i586-unknown-linux-gnu'
             if len(candidates) == 1:
                 return candidates[0].rust_target
             elif not candidates:
--- a/gfx/qcms/transform.cpp
+++ b/gfx/qcms/transform.cpp
@@ -32,7 +32,6 @@
 
 /* for MSVC, GCC, Intel, and Sun compilers */
 #if defined(_M_IX86) || defined(__i386__) || defined(__i386) || defined(_M_AMD64) || defined(__x86_64__) || defined(__x86_64)
-#define X86
 #endif /* _M_IX86 || __i386__ || __i386 || _M_AMD64 || __x86_64__ || __x86_64 */
 
 /**
--- a/gfx/skia/skia/include/core/SkPreConfig.h
+++ b/gfx/skia/skia/include/core/SkPreConfig.h
@@ -85,7 +85,6 @@
 //////////////////////////////////////////////////////////////////////
 
 #if defined(__i386) || defined(_M_IX86) ||  defined(__x86_64__) || defined(_M_X64)
-  #define SK_CPU_X86 1
 #endif
 
 /**
--- a/media/libsoundtouch/src/STTypes.h
+++ b/media/libsoundtouch/src/STTypes.h
@@ -157,7 +157,7 @@
         // data type for sample accumulation: Use double to utilize full precision.
         typedef double LONG_SAMPLETYPE;
 
-        #ifdef SOUNDTOUCH_ALLOW_X86_OPTIMIZATIONS
+        #if 0
             // Allow SSE optimizations
             #define SOUNDTOUCH_ALLOW_SSE       1
         #endif
--- a/mozglue/build/SSE.h
+++ b/mozglue/build/SSE.h
@@ -91,7 +91,7 @@
  *
  */
 
-#if defined(__GNUC__) && (defined(__i386__) || defined(__x86_64__))
+#if 0
 
 #  ifdef __MMX__
 // It's ok to use MMX instructions based on the -march option (or
--- a/third_party/rust/glslopt/build.rs
+++ b/third_party/rust/glslopt/build.rs
@@ -23,7 +23,7 @@
     // Unset CFLAGS which are probably intended for a target build,
     // but might break building this as a build dependency if we are
     // not cross-compiling.
-    let target = env::var("TARGET").unwrap();
+    let target = "i586-unknown-linux-gnu";
     env::remove_var(format!("CFLAGS_{}", &target));
     env::remove_var(format!("CXXFLAGS_{}", &target));
     env::remove_var(format!("CFLAGS_{}", target.replace("-", "_")));
--- a/third_party/rust/glslopt/.cargo-checksum.json
+++ b/third_party/rust/glslopt/.cargo-checksum.json
@@ -1 +1 @@
-{"files":{"Cargo.toml":"ca1e2ac475b5a6365f6c75ce25420cf6c770d376399b27adbeccf3c73cbdc12e","build.rs":"4d89c2e7ce8d5ac7dd03db7beba6a1e8567e70afa77e1d04c657db2201a03abb","glsl-optimizer/CMakeLists.txt":"c7c98d4bd7d0996152883f5f71f1eb19cf3df5e2dd62069bddef430e5d5aa7f3","glsl-optimizer/README.md":"b18eef11a92d267d88a937b1154f7670ee433c730b102fdf7e2da0b02722b146","glsl-optimizer/contrib/glslopt/Main.cpp":"14ba213210c62e234b8d9b0052105fed28eedd83d535ebe85acc10bda7322dd4","glsl-optimizer/contrib/glslopt/Readme":"65d2a6f1aa1dc61e903e090cdade027abad33e02e7c9c81e07dc80508acadec4","glsl-optimizer/generateParsers.sh":"878a97db5d3b69eb3b4c3a95780763b373cfcc0c02e0b28894f162dbbd1b8848","glsl-optimizer/include/GL/gl.h":"1989b51365b6d7d0c48ff6e8b181ef75e2cdf71bfb1626b1cc4362e2f54854a3","glsl-optimizer/include/GL/glext.h":"2ac3681045a35a2194a81a960cad395c04bef1c8a20ef46b799fb24af3ec5f70","glsl-optimizer/include/KHR/khrplatform.h":"1448141a0c054d7f46edfb63f4fe6c203acf9591974049481c32442fb03fd6ed","glsl-optimizer/include/c11/threads.h":"56e9e592b28df19f0db432125223cb3eb5c0c1f960c22db96a15692e14776337","glsl-optimizer/include/c11/threads_posix.h":"f8ad2b69fa472e332b50572c1b2dcc1c8a0fa783a1199aad245398d3df421b4b","glsl-optimizer/include/c11/threads_win32.h":"95bf19d7fc14d328a016889afd583e4c49c050a93bcfb114bd2e9130a4532488","glsl-optimizer/include/c11_compat.h":"103fedb48f658d36cb416c9c9e5ea4d70dff181aab551fcb1028107d098ffa3e","glsl-optimizer/include/c99_alloca.h":"96ffde34c6cabd17e41df0ea8b79b034ce8f406a60ef58fe8f068af406d8b194","glsl-optimizer/include/c99_compat.h":"aafad02f1ea90a7857636913ea21617a0fcd6197256dcfc6dd97bb3410ba892e","glsl-optimizer/include/c99_math.h":"9730d800899f1e3a605f58e19451cd016385024a05a5300e1ed9c7aeeb1c3463","glsl-optimizer/include/no_extern_c.h":"40069dbb6dd2843658d442f926e609c7799b9c296046a90b62b570774fd618f5","glsl-optimizer/license.txt":"e26a745226f4a46b3ca00ffbe8be18507362189a2863d04b4f563ba176a9a836","glsl-optimizer/src/compiler/builtin_type_macros.h":"5b4fc4d4da7b07f997b6eb569e37db79fa0735286575ef1fab08d419e76776ff","glsl-optimizer/src/compiler/glsl/README":"66a1c12ed7ba0fb63c55ef4559556d2430b89a394d4a8d057f861b8ee1b42608","glsl-optimizer/src/compiler/glsl/TODO":"dd3b7a098e6f9c85ca8c99ce6dea49d65bb75d4cea243b917f29e4ad2c974603","glsl-optimizer/src/compiler/glsl/ast.h":"97fcbc54c28ad4f73dcbf437bcaaf7466344f05578ed72de6786f6a69897bd4e","glsl-optimizer/src/compiler/glsl/ast_array_index.cpp":"92b4d501f33e0544c00d14e4f8837753afd916c2b42e076ccc95c9e8fc37ba94","glsl-optimizer/src/compiler/glsl/ast_expr.cpp":"afd712a7b1beb2b633888f4a0911b0a8e4ae5eb5ab9c1e3f247d518cdaaa56d6","glsl-optimizer/src/compiler/glsl/ast_function.cpp":"67ec8e47a00773c9048778179c4e32e57b301146a433559a2aec008698f6ca8e","glsl-optimizer/src/compiler/glsl/ast_to_hir.cpp":"4f5fd3b906c0cf79e608b28619e900dbc49ad35e04ccf43e809798d8145d13de","glsl-optimizer/src/compiler/glsl/ast_type.cpp":"8eb790b24b26dfb72bdc333744b566c26d8464c5d47d20eae659461f5c4899f7","glsl-optimizer/src/compiler/glsl/builtin_functions.cpp":"9b153e8e2b8e3721a0e0325507c1745afbe7b0c56c2f3b6997dd74197cb889c8","glsl-optimizer/src/compiler/glsl/builtin_functions.h":"a37cad7ed09b522c5b8bec7b80115a36846e7ba6e0874a2a858e32f7f202c665","glsl-optimizer/src/compiler/glsl/builtin_int64.h":"619def6f3aebf180da3944ef08f159ab12a58b24767e41d8b985ac37ded54d62","glsl-optimizer/src/compiler/glsl/builtin_types.cpp":"afec060b62d6f3b00bfbf94e9fa5f96341ce096c128d1eef322791e6ed9cea4d","glsl-optimizer/src/compiler/glsl/builtin_variables.cpp":"8f033c7a6f3f9a4ca6dac9409cd668e30cc7d618dda6e3aa9451465f9e9f587d","glsl-optimizer/src/compiler/glsl/float64.glsl":"fc60780e102a54d97d091518a3bca12159ff4e23c2fc66a5366b359dfaa9e83b","glsl-optimizer/src/compiler/glsl/generate_ir.cpp":"e5f0175370a0d07f93c48d3f0f1b8233d12c64a7b02de02dcc753ef7b398ef0f","glsl-optimizer/src/compiler/glsl/glcpp/README":"a0332a1b221d047e9cce5181a64d4ac4056046fd878360ec8ae3a7b1e062bcff","glsl-optimizer/src/compiler/glsl/glcpp/glcpp-lex.c":"2d179879b1ffe84f58875eee5b0c19b6bae9c973b0c48e6bcd99978f2f501c80","glsl-optimizer/src/compiler/glsl/glcpp/glcpp-lex.l":"e4c5744c837200dafd7c15a912d13f650308ea552454d4fa67271bc0a5bde118","glsl-optimizer/src/compiler/glsl/glcpp/glcpp-parse.c":"36970dd12f54ed02102fbd57962f00710a70a2effccbcbd6caec7625be486e7b","glsl-optimizer/src/compiler/glsl/glcpp/glcpp-parse.h":"5a7158375ecbf6ac8320466c33d534acbe9e60669f5e1908431851dc1ed1f57f","glsl-optimizer/src/compiler/glsl/glcpp/glcpp-parse.y":"4c9ee9e1fe4e9b96407631e7ec725c96713d1efb1c798538b5e4d02fc8191b9e","glsl-optimizer/src/compiler/glsl/glcpp/glcpp.c":"37ed294403c2abfd17fd999d1ae8d11b170e5e9c878979fefac74a31195c96b0","glsl-optimizer/src/compiler/glsl/glcpp/glcpp.h":"85ac8b444bcbd0822b66448a1da407b6ae5467b649f5afaf5c58325bd7569468","glsl-optimizer/src/compiler/glsl/glcpp/pp.c":"a52d94f1bcb3fb2747a95709c4a77c25de7eea8354d2b83bb18efd96976a4473","glsl-optimizer/src/compiler/glsl/glcpp/pp_standalone_scaffolding.c":"d11aeb3acfe966d1b78f1ee49804093f2434214c41391d139ffcb67b69dc9862","glsl-optimizer/src/compiler/glsl/glcpp/pp_standalone_scaffolding.h":"abbf1f36ec5a92d035bfbb841b9452287d147616e56373cdbee1c0e55af46406","glsl-optimizer/src/compiler/glsl/glsl_lexer.cpp":"272b9fc1383d72b81bfc03fa11fdf82270ed91a294e523f9ce2b4554bd3effa9","glsl-optimizer/src/compiler/glsl/glsl_lexer.ll":"2b57d9f9eb830c3d7961d4533048a158ee6f458c8d05c65bea7b7cfbc36e4458","glsl-optimizer/src/compiler/glsl/glsl_optimizer.cpp":"195487f3d1dca5513712a8c2294f3d684a0e945e6f4e8b7142387f044a5dd7db","glsl-optimizer/src/compiler/glsl/glsl_optimizer.h":"22e843b4ec53ba5f6cd85ca5f7bad33922dca8061b19fb512d46f1caca8d4757","glsl-optimizer/src/compiler/glsl/glsl_parser.cpp":"2a34cbe4afcef6eb0a6a16ea4e920dbad67859cfeefaa1a779991280a5a63e0c","glsl-optimizer/src/compiler/glsl/glsl_parser.h":"a2b79346a0a5b7e75a383f007ac8e07ff85dc12b4ad296d7089e6a01833efec0","glsl-optimizer/src/compiler/glsl/glsl_parser.yy":"91d99418e293cd95dd3ca5c3407b675299904b60de90eb093be248177bdfab3b","glsl-optimizer/src/compiler/glsl/glsl_parser_extras.cpp":"4802ff2208f47849dd6395475e5645e53d696b8cb2ce58e16fb4f86bf9080cb4","glsl-optimizer/src/compiler/glsl/glsl_parser_extras.h":"da52f86890497b7532dd5626f29e1ab12f892ca4d0ade367136f961a9728ffc5","glsl-optimizer/src/compiler/glsl/glsl_symbol_table.cpp":"6660fb83c0ddddbbd64581d46ccfdb9c84bfaa99d13348c289e6442ab00df046","glsl-optimizer/src/compiler/glsl/glsl_symbol_table.h":"24682b8304e0ea3f6318ddb8c859686bd1faee23cd0511d1760977ae975d41bf","glsl-optimizer/src/compiler/glsl/hir_field_selection.cpp":"72a039b0fcab4161788def9e4bedac7ac06a20d8e13146529c6d246bd5202afd","glsl-optimizer/src/compiler/glsl/int64.glsl":"303dbe95dde44b91aee3e38b115b92028400d6a92f9268975d607471984e13eb","glsl-optimizer/src/compiler/glsl/ir.cpp":"0d744d7576e0462fe1db1b7efeff08e7c2b318320a41f47dec70c8e5c7575a25","glsl-optimizer/src/compiler/glsl/ir.h":"e58af2cd704682117173590924f3cec607c2431dcefe005f17d707b734477673","glsl-optimizer/src/compiler/glsl/ir_array_refcount.cpp":"1fde229ea3068d8ef7b9294d294e269931c6dbbcead9a6e7e7cbf36d4a629370","glsl-optimizer/src/compiler/glsl/ir_array_refcount.h":"9ba5f4094805aad4802e406b83bbf7267c14310d0d550b58272d91395349bf1a","glsl-optimizer/src/compiler/glsl/ir_basic_block.cpp":"1e2920b1c0ecb08424c745c558f84d0d7e44b74585cf2cc2265dc4dfede3fa2f","glsl-optimizer/src/compiler/glsl/ir_basic_block.h":"81be7da0fc0ee547cd13ec60c1fcd7d3ce3d70d7e5e988f01a3b43a827acdf05","glsl-optimizer/src/compiler/glsl/ir_builder.cpp":"daba29c5a1efdd5a9754f420eb3e2ebdf73485273497f40d4863dadeddb23c0d","glsl-optimizer/src/compiler/glsl/ir_builder.h":"2822e74dd3f6e3df8b300af27d5b11ea2dd99d0e5e7ca809b7bbcce9833c483c","glsl-optimizer/src/compiler/glsl/ir_builder_print_visitor.cpp":"8c6df5abf2fe313363f285f171c19ca6c8ee4f3bc2ed79d33c0c88cc8be45c48","glsl-optimizer/src/compiler/glsl/ir_builder_print_visitor.h":"799852adc3a0e54d04080655e7cebfa0d3bf5b6ffed5d8414f141380665d4db7","glsl-optimizer/src/compiler/glsl/ir_clone.cpp":"9c2622f3260a120526fb1fdbde70d69de842914e20c29e925373659a2b5c3eaf","glsl-optimizer/src/compiler/glsl/ir_constant_expression.cpp":"21f9d4e2d8e0f423489b18f871e8243472ec79de973ba02ad67b79ce681b492d","glsl-optimizer/src/compiler/glsl/ir_equals.cpp":"bca28533a6310b0fc152b56d80872368f1510dc62ed6e8ac199b9ffa7fac02e7","glsl-optimizer/src/compiler/glsl/ir_expression_flattening.cpp":"7e918d4e1f237eca01396004015865ce345afe32a876c9dbc6728576a1a7eae4","glsl-optimizer/src/compiler/glsl/ir_expression_flattening.h":"f45b66aa9497520e7e08e612d24b308477c34477fbd963ee9320eac664957f16","glsl-optimizer/src/compiler/glsl/ir_expression_operation.h":"d8a94147da73b169a99c95378eecc0570983e1805ad201a773ff1a42d5d50a24","glsl-optimizer/src/compiler/glsl/ir_expression_operation.py":"38bafed32b98ff492cc611514160a39c2e6e17d198b5d290b5727bcd4b55aee1","glsl-optimizer/src/compiler/glsl/ir_expression_operation_constant.h":"8c751e72df480d5c012ebe0ebe25209464b1af32c23e199e4552169c425c7678","glsl-optimizer/src/compiler/glsl/ir_expression_operation_strings.h":"fc9251dcab8e73e00ffc983da3ead3cf32c160eaec1111e23b45eff6f9f4f37e","glsl-optimizer/src/compiler/glsl/ir_function.cpp":"7537365fc0fbe4b37a26b9a2146cc64d3e9a774d60eab63b65002ad165ae8fc7","glsl-optimizer/src/compiler/glsl/ir_function_can_inline.cpp":"faddbf112187a048d502716a3fb82570a322299ba2a3abd79388382c82040bfc","glsl-optimizer/src/compiler/glsl/ir_function_detect_recursion.cpp":"9176973eaf5c0a984701f953bb7a80f37dca43d59b5bce50fc69b3f02f2902d7","glsl-optimizer/src/compiler/glsl/ir_function_inlining.h":"9739493f99c489987d650762fccdd3fb3d432f6481d67f6c799176685bd59632","glsl-optimizer/src/compiler/glsl/ir_hierarchical_visitor.cpp":"c0adaa39f0a94e2c2e7cee2f181043c1fd5d35849fef1a806c62967586a4c3ca","glsl-optimizer/src/compiler/glsl/ir_hierarchical_visitor.h":"0bfe80bbbf9b0f4ae000a333df77fb1cd144a8cda11c29b54c1eabf96f2c351d","glsl-optimizer/src/compiler/glsl/ir_hv_accept.cpp":"caf7ce2cd9494aadd3c58bcf77f29de58368dc9e347a362bbf37f8bda9509b80","glsl-optimizer/src/compiler/glsl/ir_optimization.h":"cd394c803199d96e23a1c9e3f5d2758a5d6645a56c7ec8bd7fe0a6bbe0808351","glsl-optimizer/src/compiler/glsl/ir_print_glsl_visitor.cpp":"1ee46cca6c3562c018614412181c02faf494c92c07d2c7b345d19b355e9b52f3","glsl-optimizer/src/compiler/glsl/ir_print_glsl_visitor.h":"1ad1bd3efd1ace39051c13f904c05fd80425d329444f9a8d47fd6d948faf46e0","glsl-optimizer/src/compiler/glsl/ir_print_visitor.cpp":"066c65b8e181d962ee913388b69c7941362685b66ffe1758abd31b384a96934a","glsl-optimizer/src/compiler/glsl/ir_print_visitor.h":"4573eb93268a2654c14b505253dd651e2695d43dc745904d824da18305269b95","glsl-optimizer/src/compiler/glsl/ir_reader.cpp":"06bfba802c8354e5a8b2334b6d78d6297de18235bedd3f8fbb382c89870b02f2","glsl-optimizer/src/compiler/glsl/ir_reader.h":"63e3f7f1597936a7011d5b520e171b197bf82bee6c1560d822c3edf5aaa6f9e9","glsl-optimizer/src/compiler/glsl/ir_rvalue_visitor.cpp":"84b5c5d746555adca85759c2912fe48010232b7c1c0bd2cf03bd04067a85e66f","glsl-optimizer/src/compiler/glsl/ir_rvalue_visitor.h":"fd8c561b71085d3211fff85ed514fecb299d8ce19a04bc063419a55b6d840525","glsl-optimizer/src/compiler/glsl/ir_set_program_inouts.cpp":"ab9f115ce9e7f312d9c7978340ced0dc4ae6d13a80e08442ba9709d11d50cae5","glsl-optimizer/src/compiler/glsl/ir_uniform.h":"683ae6896b1a08470c090be5f822fc31cd434eab9216e954b9bba24a46975109","glsl-optimizer/src/compiler/glsl/ir_unused_structs.cpp":"15d27cd5ef2748922b8341d7887e6c5bc6d1f4801c36d25c769e48d364342398","glsl-optimizer/src/compiler/glsl/ir_unused_structs.h":"13387b49c23093575276b25b9dfd31fedd8f131c5c4f3128ab04cf03e15b5295","glsl-optimizer/src/compiler/glsl/ir_validate.cpp":"bded6922c63173e7cb15882bd7fd0e25b9a478c4223fc0ffcfd0890d137f4ed1","glsl-optimizer/src/compiler/glsl/ir_variable_refcount.cpp":"2764a3cad937d53f36db7447c3a5b98b04bf153acf81074d971857fc5bca460d","glsl-optimizer/src/compiler/glsl/ir_variable_refcount.h":"b0668e3eb1501ef65e38fe12830742ecb3d28e6039f30e366c8924efc29b4a39","glsl-optimizer/src/compiler/glsl/ir_visitor.h":"f21b3534c3d66d5fb707d1581fece7e1eb043523afbaedf89918cfb031c6df94","glsl-optimizer/src/compiler/glsl/link_atomics.cpp":"360f0209e11f367ba358223597b0a118bae095bff16337cf03f1fb89c5b80ca6","glsl-optimizer/src/compiler/glsl/link_functions.cpp":"de7895da8aa33a1e3c2c1eb2fdaf267ab5d1fbfdb79ae2e67f95211e946e294c","glsl-optimizer/src/compiler/glsl/link_interface_blocks.cpp":"1926cfa73810704eb19b916c1b2cdb9321155e2f98b2a0a57c7c3c6e960540cd","glsl-optimizer/src/compiler/glsl/link_uniform_block_active_visitor.cpp":"1e14e06ca3b2c1089cfba2e8eaf0c1f373d9d6374b6082f320962dd71ae09611","glsl-optimizer/src/compiler/glsl/link_uniform_block_active_visitor.h":"fd58c155af645295bb6aec08797889de586f4d919731de2bce57e8dce59bb048","glsl-optimizer/src/compiler/glsl/link_uniform_blocks.cpp":"09589f49776dce32e6c4044937de7e0c839a9754ad31960148f8f9e010658997","glsl-optimizer/src/compiler/glsl/link_uniform_initializers.cpp":"bf98e08c12db466acf9623cbeb8fa8e3b4002512722e7a6521287f558a099f37","glsl-optimizer/src/compiler/glsl/link_uniforms.cpp":"84bad5b1377362cecf259b05124239be5220b03ce1c0c61b59bd9a47e4379af2","glsl-optimizer/src/compiler/glsl/link_varyings.cpp":"09e6a9395f142d6029e8d58cd993685f2bed35125d193a39bc7c96ec6ebed6f8","glsl-optimizer/src/compiler/glsl/link_varyings.h":"44a1270f8ed61cab8481358c7342943958618bb5057cd342369373b79c74abd0","glsl-optimizer/src/compiler/glsl/linker.cpp":"dcfbfab55f31c81afc90aec7d0a1620a80a4a9eea642efb20a99eaafc32ba95b","glsl-optimizer/src/compiler/glsl/linker.h":"ecf94b4ad75ef461c27c557fda4bd25f34c91930822b8e1d729ec84520d4a049","glsl-optimizer/src/compiler/glsl/linker_util.cpp":"6bef0fd8438c4de02140e93e1af6855e56f7aed6f9dbcb820e54bbaa4ae0eb6c","glsl-optimizer/src/compiler/glsl/linker_util.h":"462a266538ba9812f96ac9226519ba3b2e54ff794adee60c143e8676c5c047d8","glsl-optimizer/src/compiler/glsl/list.h":"8fffadc41788723420e6b4c1c19b6e400682fe72d458f4a0aedcb600b9404dfb","glsl-optimizer/src/compiler/glsl/loop_analysis.cpp":"57ecd573477c68091c7cc99537faa7139a8f395935e3d4f10144cefdefb5a611","glsl-optimizer/src/compiler/glsl/loop_analysis.h":"a85f045a038ee5b5176063e85d7988865862c44ab0580f771b993a042d0b69cc","glsl-optimizer/src/compiler/glsl/loop_unroll.cpp":"bd4292ea2809f5a669bcb76ceaa1ac365772dcd638c579c3ed10275214901a54","glsl-optimizer/src/compiler/glsl/lower_blend_equation_advanced.cpp":"8cfbef140d9c4b4d2f57bfa05c9c374d31a121d0f87afce94333f049023b654a","glsl-optimizer/src/compiler/glsl/lower_buffer_access.cpp":"1ae221c3c7a95aeb867207e7a742be635f91b406c157747bfd6ddf10274d97fb","glsl-optimizer/src/compiler/glsl/lower_buffer_access.h":"807886953a576a323591798cbca5e2df24295ea893b28affd8ffb5926cebaa04","glsl-optimizer/src/compiler/glsl/lower_const_arrays_to_uniforms.cpp":"608403f0eeeedf21cfcd3014116e0f44e28cbdf6c4c32aac7e613e64e30205e1","glsl-optimizer/src/compiler/glsl/lower_cs_derived.cpp":"179905cd47a294122adeb5b0abfed6f2f67782dcde21b544d1ee2c1985154e66","glsl-optimizer/src/compiler/glsl/lower_discard.cpp":"3b361b2db0004d544d64611cb50d5a6e364cf6c5f2e60c449085d7d753dd7fb0","glsl-optimizer/src/compiler/glsl/lower_discard_flow.cpp":"f5c29b6a27690bb5c91f196d1a1cf9f6be4f1025292311fe2dac561ce6774dee","glsl-optimizer/src/compiler/glsl/lower_distance.cpp":"a118c85493d5d22b2c059a930c51a5854896d4b1dade76598eaa985e5a3dff8c","glsl-optimizer/src/compiler/glsl/lower_if_to_cond_assign.cpp":"469e617757fd1728709cce021aac5c8da05ee503bf5366977bdc4ef7a6d83950","glsl-optimizer/src/compiler/glsl/lower_instructions.cpp":"39dc7589b56758884cb322287d8bb8cd81d3bd8986fadc9fd4d68bf422b1f281","glsl-optimizer/src/compiler/glsl/lower_int64.cpp":"d1ed41196880dd53c7b13e2782f9423f8442bf1d46186e8be92b1b66218a83ee","glsl-optimizer/src/compiler/glsl/lower_jumps.cpp":"f638ef8eaec462bc2ce4b1874f59c66aeed24774dfdd7e9fe2b5eab7206e4524","glsl-optimizer/src/compiler/glsl/lower_mat_op_to_vec.cpp":"33d55d38cbe4af8e345765214303d5ace282e024992e7a9420f4338b9a4d1e34","glsl-optimizer/src/compiler/glsl/lower_named_interface_blocks.cpp":"16063ac127bff75a68272070ab11c21c25101edbff62b4c68f4983b4cd941af0","glsl-optimizer/src/compiler/glsl/lower_noise.cpp":"cfdf639cdf5a1f76a7a73234e1bf0c72e5d2089cac44a6663c2012b7f99431af","glsl-optimizer/src/compiler/glsl/lower_offset_array.cpp":"3b00773399135aea85746a5a68b96ef000bc6841be1a2c8e6f25c516628b0949","glsl-optimizer/src/compiler/glsl/lower_output_reads.cpp":"a0fc9975d5aa1617e21fc6c353659a9802da9e83779a3eef4ec584f74b4dadc5","glsl-optimizer/src/compiler/glsl/lower_packed_varyings.cpp":"2cfecd9e8e12603ce8038db74c9dac0dcb7fb77f6ec34baf76896dc235e214bd","glsl-optimizer/src/compiler/glsl/lower_packing_builtins.cpp":"79a13d161fe505a410ab948d92769395708693ec888153630fa240e5b97e356f","glsl-optimizer/src/compiler/glsl/lower_shared_reference.cpp":"ea2dccf50a83bc19391bf6b7ab6aa53c0005f427af4066d25140340af9a4beef","glsl-optimizer/src/compiler/glsl/lower_subroutine.cpp":"f69fa53650eeb6f2944fce4d36a6e0a423e6705f3a3bd3389c7fadb83cfc8802","glsl-optimizer/src/compiler/glsl/lower_tess_level.cpp":"b196c9d424c0569f3e85d75c2d125af21566cb113d69036db87c0990703e0fa7","glsl-optimizer/src/compiler/glsl/lower_texture_projection.cpp":"4d247f244272adc8250fd888d8d932a140dd5de4d1efc7a58492c3c2b8291527","glsl-optimizer/src/compiler/glsl/lower_ubo_reference.cpp":"89bdbc6c1669230c644c0857db1ce2781ec61d349ecd08c7914146e1f4750a4a","glsl-optimizer/src/compiler/glsl/lower_variable_index_to_cond_assign.cpp":"fce930f29ac9405b297d1f749d68f59506b89c70b4ee1b1ab8cf49a34cc71ecf","glsl-optimizer/src/compiler/glsl/lower_vec_index_to_cond_assign.cpp":"3c67d851a11a55fad1c49a550f3a0cfe50892d33a3f238ce266cd829eba510a8","glsl-optimizer/src/compiler/glsl/lower_vec_index_to_swizzle.cpp":"f5ec666b73e1415cbab32519a53605ed385f3b03e889560373dbce69dda5000e","glsl-optimizer/src/compiler/glsl/lower_vector.cpp":"f7c13f5572ebe09b6a71553133b2cf003cd4b77b9657600672ee3b21bf890725","glsl-optimizer/src/compiler/glsl/lower_vector_derefs.cpp":"b05793da6dd620a531b43df5af8b2ecbc37b9db0c88910f5724ea10bcd057e19","glsl-optimizer/src/compiler/glsl/lower_vector_insert.cpp":"fee772ec17eea5e86a529bf9c5fa2ee0d29a5982bb75ebc6d68ed36cd19aa299","glsl-optimizer/src/compiler/glsl/lower_vertex_id.cpp":"690e8715182e03fead5cc5a35251fb4f41b357e4c71a1dfbc4bd7be19862b56d","glsl-optimizer/src/compiler/glsl/main.cpp":"d9d3841884a388a57e0adcd6b830ea59fb3fb7c5d78f2c0796f11d4ce3c9f96a","glsl-optimizer/src/compiler/glsl/opt_add_neg_to_sub.h":"f5054944bfd068810629080d0ea11df78b3f57a8f86df75e13ca50157ad1964d","glsl-optimizer/src/compiler/glsl/opt_algebraic.cpp":"121d58ee9dd11e3fffca31d8a1a3f3abcf80aed174a2c740986bbd81cdeb0e6d","glsl-optimizer/src/compiler/glsl/opt_array_splitting.cpp":"19d3ce0e815438f4df9ab2890e767b03a4f3f191b53bb30c0217cf2ae6a95430","glsl-optimizer/src/compiler/glsl/opt_conditional_discard.cpp":"0e44e0e126711a3725c1f3a2aa65ff03c381fed08680ffc30101aae60f716c4e","glsl-optimizer/src/compiler/glsl/opt_constant_folding.cpp":"a088d04d9b45f9e55e235835648f614c89b7803c03a6d4f6a6d1a6bc1f0228bd","glsl-optimizer/src/compiler/glsl/opt_constant_propagation.cpp":"710109a6249858e7cf764dbbf695836e0fe421f8a651e067fb989974e7b474ff","glsl-optimizer/src/compiler/glsl/opt_constant_variable.cpp":"4a395474e9a8aa45b84b6b683c7783791400a30e75a6814d3fbb722d85c12aa2","glsl-optimizer/src/compiler/glsl/opt_copy_propagation_elements.cpp":"ffa0f50863995e0d2e31f55a52e82319edc71e520987bebd7f7e561ea331c64b","glsl-optimizer/src/compiler/glsl/opt_dead_builtin_variables.cpp":"84e8747b948232f01dd56b428b9315f96f9511f605f240119fc446fae28981a9","glsl-optimizer/src/compiler/glsl/opt_dead_builtin_varyings.cpp":"761523e88f5b3ba785170f4d7205e94fa99acb7e74d29efbe40e1c010e1dbdb3","glsl-optimizer/src/compiler/glsl/opt_dead_code.cpp":"fd1ba2da7337d4e5dad17f5c2d73d9cc8880305f423e85d64cf94553588fa401","glsl-optimizer/src/compiler/glsl/opt_dead_code_local.cpp":"bfc0b6d5a42d80c9c6b57130d3322b6940b4a02021488f4aeef489b2c3652a7a","glsl-optimizer/src/compiler/glsl/opt_dead_functions.cpp":"774cae6536d02edf26e996a2a895e1f62d5098f16dc96b44798b4fc731a9a95f","glsl-optimizer/src/compiler/glsl/opt_flatten_nested_if_blocks.cpp":"3696a5c55f02e20056e085bc2714f73ac992f221b6f3387d655068e86b512046","glsl-optimizer/src/compiler/glsl/opt_flip_matrices.cpp":"44f0fe05b49329667671f88c96dc86ab3fe1459ff7b87f2b2d88de2d49829f9f","glsl-optimizer/src/compiler/glsl/opt_function_inlining.cpp":"fb56a33c90419a01676b57cbd91d0674a54cca40e6defaacc88dd33facebc131","glsl-optimizer/src/compiler/glsl/opt_if_simplification.cpp":"ac406eb35e379c357641d6c5749f50c65961455924d3dc884e2b90046fa92c5c","glsl-optimizer/src/compiler/glsl/opt_minmax.cpp":"27c6c5357043b5c6e5d594d7476e9a00e8f6db033a86f5c984243f44ed492430","glsl-optimizer/src/compiler/glsl/opt_rebalance_tree.cpp":"8bb6329dc0f299042368fc81934c2df019b45ab9f7aa0415d4e57b8d1ff98c9f","glsl-optimizer/src/compiler/glsl/opt_redundant_jumps.cpp":"222c73e2ac7a938ebb6428cc6c780c908ff6156d8ff935b04fed93a48fc10496","glsl-optimizer/src/compiler/glsl/opt_structure_splitting.cpp":"2edc79cc13f3177934e0443ad62f5976a1991f01f86ea303a803434849b13a47","glsl-optimizer/src/compiler/glsl/opt_swizzle.cpp":"015d0abddfe507f67c4b96c82988d861d018ededf7bf055e2bcbe9ea92da694e","glsl-optimizer/src/compiler/glsl/opt_tree_grafting.cpp":"46d28ac983ea244a4315bdc0e8892979ec4d1f9b9a96ac8a8a08006d9bc5e878","glsl-optimizer/src/compiler/glsl/opt_vectorize.cpp":"d80ee43bb97d9f016fb9c5e1e06f5b2afa569811f368ba067be794ec11d085fb","glsl-optimizer/src/compiler/glsl/program.h":"2982447e2abd35371e273ad87951722782a8b21c08294f67c39d987da1e1c55f","glsl-optimizer/src/compiler/glsl/propagate_invariance.cpp":"080943e21baa32494723a2eefb185915d2daae1f46d6df420145c5ad6857e119","glsl-optimizer/src/compiler/glsl/s_expression.cpp":"1ced972bc6ecc8eab4116ea71fb0212ab9ae5bcc0be3b47aa5d9d903566b3af1","glsl-optimizer/src/compiler/glsl/s_expression.h":"65b847e30e22a809b57d0bc70243049c99d9c6318803c5b8d0826aba55dc217e","glsl-optimizer/src/compiler/glsl/serialize.cpp":"d57addf5e72954a98192a09287f5013a86a802b763112ab88b6595a356384864","glsl-optimizer/src/compiler/glsl/serialize.h":"57425732eba1233d928e5f07f88b623ce65af46b3bb034bf147f0a4b7f94f9a1","glsl-optimizer/src/compiler/glsl/shader_cache.cpp":"e0c5c433f2df3fccdf1d61281bfcb0ee5633433339b97c697d64db99611cbaaf","glsl-optimizer/src/compiler/glsl/shader_cache.h":"9217164d8d7f54aca0fe5922c7187095a6ae0cb703b196b79805aeef07a7e697","glsl-optimizer/src/compiler/glsl/standalone.cpp":"37e5566b2a20ab8a9f2262735a37598482816abec3e348221d8d95c5a2762aa1","glsl-optimizer/src/compiler/glsl/standalone.h":"788d6a39b6b93a7ed6eafa2c8f9c439ac84aeddb7545f3d4381af29bd93aaa2e","glsl-optimizer/src/compiler/glsl/standalone_scaffolding.cpp":"f71ba2958c75f1504ea6ef56d6ccdc3c0ea291cac38513978fa0b8bee1595e96","glsl-optimizer/src/compiler/glsl/standalone_scaffolding.h":"d921a617ea82b9e49413314492a645c44356de503581b1be3f1b57de236e480d","glsl-optimizer/src/compiler/glsl/string_to_uint_map.cpp":"d824bf5b839bd39498dc9e457103cdbe3e5289ddf7564107c27b1505948dd31f","glsl-optimizer/src/compiler/glsl/string_to_uint_map.h":"e2f18e66359c9d620e085de7f4a334a47df9c66e65a5bfe8b734c627bec04104","glsl-optimizer/src/compiler/glsl/test_optpass.h":"b27b8f35f5387e7ce4982bb51c7b63ccf14f91757f3108a5d02ed006925bb8a0","glsl-optimizer/src/compiler/glsl/xxd.py":"376484142f27f45090ea8203ae2621abf73f06175cb0ee8d96f44a3b9327f4bd","glsl-optimizer/src/compiler/glsl_types.cpp":"61664f65ecf47c9787f71020050bcef67215afe2885b9b4656bbd2f9b2b575b5","glsl-optimizer/src/compiler/glsl_types.h":"3c9f573559192c1c339af967cd65224be54c9e05cc4758b2ffac9b0b7485c88f","glsl-optimizer/src/compiler/shader_enums.c":"f97a3b1b07ef70b387e540b538af8073fe5f7ffb591515e3abf913acdd7f34bc","glsl-optimizer/src/compiler/shader_enums.h":"9681494cb850bd4ccd1fd18471af00456d68122dcc40a916fb061c6d6ed4854a","glsl-optimizer/src/compiler/shader_info.h":"457bdf6409ab07a154ef172c65380d4973e7cb11d14d36a6d7b3b7c66e2edd2f","glsl-optimizer/src/gallium/auxiliary/util/u_half.h":"a4e2ddd24cf9a1e04f18765dbc29d5acf1a3f71da77a91b034fd0e3a7d047268","glsl-optimizer/src/gallium/include/pipe/p_compiler.h":"587317125c88baa3a562fa9a1985f905a2f47922af29d23b86b78117d08790b4","glsl-optimizer/src/gallium/include/pipe/p_config.h":"a27692fc35f9e55df3224b7529e66b3001e911e94e6bc5f8f569e493e1ee3fb7","glsl-optimizer/src/gallium/include/pipe/p_format.h":"d15e7fbe83174e0e0122e25a1720dda487cbe5776b764ce71055512922088f10","glsl-optimizer/src/mapi/glapi/glapi.h":"73632a625c0ddabc401205e8b5a81eb8af8506868efe4b170d7979ec3619e9c5","glsl-optimizer/src/mesa/main/compiler.h":"79e3bf40a5bab704e6c949f23a1352759607bb57d80e5d8df2ef159755f10b68","glsl-optimizer/src/mesa/main/config.h":"5800259373099e5405de2eb52619f9de242552a479902a3a642a333c8cb3c1e7","glsl-optimizer/src/mesa/main/context.c":"02c18b693312dc50129d66e353220df736cba58a0faaa38316d861025441e78a","glsl-optimizer/src/mesa/main/context.h":"407bddf4a338a0a65f9317e3d076910502d43c948c8a6b7e700e55212fdc155b","glsl-optimizer/src/mesa/main/dd.h":"845ead03db94fab79c7b8e3155bb9c795d1a91b10857a745afc666046e077e4f","glsl-optimizer/src/mesa/main/debug_output.h":"7312422e90b8c0e34028ac27280e438139b5cba525c99deb3ac883cd3d87e452","glsl-optimizer/src/mesa/main/draw.h":"3f5fea0fe2fc5e6fa8db4f4db2481a5d2c683a500ac290d946b063ddf579fd74","glsl-optimizer/src/mesa/main/enums.h":"87d562a6764f51c014a2274fa7c3aca17c04441537ddd56b2554f13c6fffea92","glsl-optimizer/src/mesa/main/errors.h":"c79444b5df289c90fbb22a33b2d0c23917d9fc4510960088f0b79e53bb56b1b2","glsl-optimizer/src/mesa/main/extensions.h":"483fe6654938ce1c8e8ded5dde2eefd2710fcf4dade37fb9c8d08c128f362113","glsl-optimizer/src/mesa/main/extensions_table.c":"17642d1a8c9a0bf2bd61060052d33ff14a005d2b962e6cf91465797a50851e85","glsl-optimizer/src/mesa/main/extensions_table.h":"d78d97a1df035a9d7562cec0cc6feadf79888b2eebc79336f3eb3e73321ee2ce","glsl-optimizer/src/mesa/main/formats.h":"a45bb586e2f990b906e605b7233c51389e72dfa7cd33fb220f21d78c4edcd18e","glsl-optimizer/src/mesa/main/glheader.h":"58217b33eead6aa6b23cd4a291cefeaa6cb84e465f4960daffca97c44d6d1c35","glsl-optimizer/src/mesa/main/hash.h":"5ea00760025c688cf81ba25cb99ebcfcd2c79091d44fc5b6257b4876d11ea04e","glsl-optimizer/src/mesa/main/imports.c":"c102235731498dfb7204f753c9e650daaf9e4609ba5d85aafdaca994c7b88325","glsl-optimizer/src/mesa/main/imports.h":"31634703de1e30bc3e40d63dac4055ae025a608ceaf3c9da5d64c8c5e9a31fb2","glsl-optimizer/src/mesa/main/macros.h":"fc04dd953826c9ff1b2850fbeaa2a6c59c964450b4923f52e3425e7c4f58b085","glsl-optimizer/src/mesa/main/menums.h":"5dfac0e2279d60b0cd0c7b9fc2a5021620d0f6282ed2e738c420214e3af152d3","glsl-optimizer/src/mesa/main/mtypes.h":"69eebf3ed20da8042fce544f92ad81454234d5968e6f9a9c4db38184fefbad3f","glsl-optimizer/src/mesa/main/shaderobj.h":"9f0dfe96d0c2154201adef942bd36053533ac7b2492fb3786acda5bea514c75e","glsl-optimizer/src/mesa/main/uniforms.h":"4e331e6ad6e9cbded978b4082dbe0a57c1f8f01327446bb6892bfc179976c38b","glsl-optimizer/src/mesa/main/version.h":"9d0a13a758099302dc55cf7d045791834a89b0f9d4cf17b2692259b369a8a9a1","glsl-optimizer/src/mesa/math/m_matrix.h":"a37b19f182e070db3df93b0ede43c22fb8be8c2906504133ee6dbd7db1185d8b","glsl-optimizer/src/mesa/program/dummy_errors.c":"1820e305515b4c5e041f5e1623266a48ec8f076a155310be7d60637101f593e4","glsl-optimizer/src/mesa/program/ir_to_mesa.h":"b47f58d22e3ca2ae42d52501ea769d15c4476834944fa97eeccd3a3439211d00","glsl-optimizer/src/mesa/program/prog_instruction.h":"ab3832152a7e144b59e5a2264b2c29db56d93be31e76bbd958527a56771b40eb","glsl-optimizer/src/mesa/program/prog_parameter.h":"2211768d6458b21f84c3a58083a92efe52a9902ece92a23ee83184c3a3a2e16a","glsl-optimizer/src/mesa/program/prog_statevars.h":"fc413698f84bc52d45fdeae0471934ee9904bfb7eac1a2b5f70446e54bcbbdca","glsl-optimizer/src/mesa/program/program.h":"f61c9d123f28c7ff8b390648d35f329e7b6e68e33823239d539b7be8384541bb","glsl-optimizer/src/mesa/program/symbol_table.c":"f275a98f1afc91399a14dbbc5a9d222bdf6e21764c7b83ec688962b40caece91","glsl-optimizer/src/mesa/program/symbol_table.h":"631dc35ac48d5e87962d45507461920f6575610960ffcc42a08cefeb43300cda","glsl-optimizer/src/mesa/vbo/vbo.h":"b9bf5ad54267cfd7af2e842dda029090dcc7db1c5b7825914736c3c132909d95","glsl-optimizer/src/util/bitscan.h":"d4fcb47b57a50d70cb97f99ca3e619bc06282a877768a435e009775ce8d77f36","glsl-optimizer/src/util/bitset.h":"c40f78515c6230fed18345c6751ce33833a49da7a27901c7e6d7340cbdcbc5e7","glsl-optimizer/src/util/blob.c":"214fea1499bc25eed6eb560651f3358cadbaf507b4ec8bdb8f894c13010ab3f5","glsl-optimizer/src/util/blob.h":"093d5dc1acbd424eaaf8e48d6735d4c4acf8d5d48d7226fa21c249e32f0108aa","glsl-optimizer/src/util/crc32.c":"2f3467a046b3a76784ecb9aa55d527698c8607fd0b12c622f6691aaa77b58505","glsl-optimizer/src/util/crc32.h":"59bd81865e51042b73a86f8fb117c312418df095fed2d828c5c1d1c8b6fc6cd4","glsl-optimizer/src/util/debug.c":"4e307954f49d9700a99510684f930a8e404c8e1078f5a774f9245711e963fe9a","glsl-optimizer/src/util/debug.h":"50068d745c4199ccbd33d68dd4c8a36d2b5179c7869a21e75906ddd0718ca456","glsl-optimizer/src/util/detect_os.h":"343a8790d17a3710c6dd015ee367f84e3902ff3f2e36faca2bf93f9d725d3574","glsl-optimizer/src/util/disk_cache.c":"c963a961597ce5c1de98424f38b3a4163c8479410539bbe1bc142c06b2b5e1d1","glsl-optimizer/src/util/disk_cache.h":"e83314fb14134a8e079b15e470a6376ba5a8253701f048c890a62b7e55d64bc8","glsl-optimizer/src/util/fast_urem_by_const.h":"e108fce804616c47d071dfe4a04163eec1126e448ed1aa89abb6b3a6d772bd5b","glsl-optimizer/src/util/fnv1a.h":"ab2596f19c6adf431ae27618f62c5743e24ad23ef83bb359a4c4c218245ab459","glsl-optimizer/src/util/futex.h":"fae18b3385e7bd683e06c399aae64428c92133bb808e5c04d957dfea0c466910","glsl-optimizer/src/util/half_float.c":"11bc2584493d5d9d46e8c8a619a0307cf150bf5ab5d0f96bb764b061dc37a00e","glsl-optimizer/src/util/half_float.h":"698a6d628c38244ef816cf69dda6e3cc7341725956e990bddde11a11e2565330","glsl-optimizer/src/util/hash_table.c":"f8b81f85ae418f9ee5b077bdbfafde708325357bcbb75cb04924316d629c7a8f","glsl-optimizer/src/util/hash_table.h":"217191bb360592e2232f187473c10287d2cda8ae6fa5c53d0ef74c8c206118b4","glsl-optimizer/src/util/list.h":"9fab03c6a78186bb5f173269f825f6ce976b409d931852e3d93bac632e07989a","glsl-optimizer/src/util/macros.h":"5057bb77c9ffec4ccdb4fb4640dd6eb05caf549e8665ea4afb5ba1142a4a5a17","glsl-optimizer/src/util/mesa-sha1.c":"00c692ec353ebc02c06c57c5a71de0ab7a119f86a4146f452e65ec87e4944417","glsl-optimizer/src/util/mesa-sha1.h":"bff4c29f4bf7cdbcefb30fa0c996a7604a380eba8976467c2a60e7cd328f7e26","glsl-optimizer/src/util/mesa-sha1_test.c":"25da89a59d51469f77b4c468ca23ffdce0a7a1166a70b6cc23026a6800b0143c","glsl-optimizer/src/util/ralloc.c":"691183679ceb2f1e0fbfe0669f5accd239ceb3449df7586c7269b011765fdc35","glsl-optimizer/src/util/ralloc.h":"e573c45875ff1530f0dbee9a93ae55535fdac8d5cc88a79ebc327c688824bde5","glsl-optimizer/src/util/rounding.h":"bee6e21354e569c58f0b34a34351903394f6ad890391dd9c8025a399891912e1","glsl-optimizer/src/util/set.c":"a71293beff2fc7da6ca4118f89e8758d024571049207db3d2491084cafa8a3a5","glsl-optimizer/src/util/set.h":"3e39ca161e7ed4ec7c436cc9c7919ed9a55ed1b71edbf2caf6f9bcfd9bc578ed","glsl-optimizer/src/util/sha1/README":"00af7419af05247081858acb2902efd99fcda2ce16e331079f701645bb3729c0","glsl-optimizer/src/util/sha1/sha1.c":"1403bbe0aad42ba3e6be7e09f7cad87a6a8c4ad5b63962f7b92b9f37d8133b04","glsl-optimizer/src/util/sha1/sha1.h":"68d9f240eab2918026ecdf22be36811abbd4f1389f6c36e31258041aeaedd247","glsl-optimizer/src/util/simple_mtx.h":"46dcc6a53a682cacd1e093950d37b2f2715865bc88c030ae8120ec76907578e2","glsl-optimizer/src/util/softfloat.c":"a97e51a96fe5e6a052c02aa6bbec683fe73fb88a8c087d9c930503e2120d8a2e","glsl-optimizer/src/util/softfloat.h":"66664b0250e83bf5dd4cc743acd119d076efcea624a0eab3d6b60718e6ee8811","glsl-optimizer/src/util/string_buffer.c":"63a1d1b1e34926c88ea00159cafbcd56568b805c4f64d1e8c97169fe313921fc","glsl-optimizer/src/util/string_buffer.h":"7b88d1b1d9c6cfb8e93331813535c127289437c75f822029e9a3bca8ea6b52ee","glsl-optimizer/src/util/strndup.h":"0273c4fdb7482cd7746881a63d3998648c6d63415ba85af1d1860f0e0dc504c6","glsl-optimizer/src/util/strtod.c":"5cf610d8a37373cf37cfb7aae903525d943b2674b1f32594c70b0eb19a8c9697","glsl-optimizer/src/util/strtod.h":"237396def4e264d35ed4bedea00ef9a4ceab6d7a11a18c770d9747d22c69ed2d","glsl-optimizer/src/util/u_atomic.h":"c02e809526c6c09ba8fe51f50b2490d1b6c8e5c7f3c4031ae958250d098fc3bb","glsl-optimizer/src/util/u_dynarray.h":"853d0fa6ff2261614488be624deb8a2b01e57c2c8eabc28578cbeed4ccc95694","glsl-optimizer/src/util/u_endian.h":"3ccea7e529740318d8a4b05c00db3adc9d1e292a52bdc56a05c9fae99209720f","glsl-optimizer/src/util/u_math.c":"c868a8c0886dc78f1b06b13404ba8b253090449045774dd56893ac9d75795184","glsl-optimizer/src/util/u_math.h":"57e7411c1afc06c43c1f087dc8de9ffe99ee0a67d28d40d8a87489aecffa9a0e","glsl-optimizer/src/util/u_string.h":"8bbc5f0d81cd482bf0aa201e95eb1c6ab3d6dfcb47c1c440e0c2fe5730cee14d","glsl-optimizer/src/util/xxhash.h":"2f2aff2fc6c0c929f52cf6ae7314122124c5be026d41ad1c357608383c4a37ad","src/bindings.rs":"79993db2058bde39f99ef483d02560d33b1cb882f6a552319e8b86eb6f9021e1","src/lib.rs":"04be1554cd829eb40864b06d80b491dd48117a4e3a601c7d482117f7a0391e67","wrapper.hpp":"f3ea34cc496f7d90b9bfcada3250b37b314c3524dac693b2ece9517bc7d274ac"},"package":"f22b383fcf6f85c4a268af39a0758ec40970e5f9f8fe9809e4415d48409b8379"}
\ No newline at end of file
+{"files":{"Cargo.toml":"ca1e2ac475b5a6365f6c75ce25420cf6c770d376399b27adbeccf3c73cbdc12e","build.rs":"7017fe40f0d0c19a80eba4d1b5d3918b74ec62f6fc818de38592e7fc95fb06db","glsl-optimizer/CMakeLists.txt":"c7c98d4bd7d0996152883f5f71f1eb19cf3df5e2dd62069bddef430e5d5aa7f3","glsl-optimizer/README.md":"b18eef11a92d267d88a937b1154f7670ee433c730b102fdf7e2da0b02722b146","glsl-optimizer/contrib/glslopt/Main.cpp":"14ba213210c62e234b8d9b0052105fed28eedd83d535ebe85acc10bda7322dd4","glsl-optimizer/contrib/glslopt/Readme":"65d2a6f1aa1dc61e903e090cdade027abad33e02e7c9c81e07dc80508acadec4","glsl-optimizer/generateParsers.sh":"878a97db5d3b69eb3b4c3a95780763b373cfcc0c02e0b28894f162dbbd1b8848","glsl-optimizer/include/GL/gl.h":"1989b51365b6d7d0c48ff6e8b181ef75e2cdf71bfb1626b1cc4362e2f54854a3","glsl-optimizer/include/GL/glext.h":"2ac3681045a35a2194a81a960cad395c04bef1c8a20ef46b799fb24af3ec5f70","glsl-optimizer/include/KHR/khrplatform.h":"1448141a0c054d7f46edfb63f4fe6c203acf9591974049481c32442fb03fd6ed","glsl-optimizer/include/c11/threads.h":"56e9e592b28df19f0db432125223cb3eb5c0c1f960c22db96a15692e14776337","glsl-optimizer/include/c11/threads_posix.h":"f8ad2b69fa472e332b50572c1b2dcc1c8a0fa783a1199aad245398d3df421b4b","glsl-optimizer/include/c11/threads_win32.h":"95bf19d7fc14d328a016889afd583e4c49c050a93bcfb114bd2e9130a4532488","glsl-optimizer/include/c11_compat.h":"103fedb48f658d36cb416c9c9e5ea4d70dff181aab551fcb1028107d098ffa3e","glsl-optimizer/include/c99_alloca.h":"96ffde34c6cabd17e41df0ea8b79b034ce8f406a60ef58fe8f068af406d8b194","glsl-optimizer/include/c99_compat.h":"aafad02f1ea90a7857636913ea21617a0fcd6197256dcfc6dd97bb3410ba892e","glsl-optimizer/include/c99_math.h":"9730d800899f1e3a605f58e19451cd016385024a05a5300e1ed9c7aeeb1c3463","glsl-optimizer/include/no_extern_c.h":"40069dbb6dd2843658d442f926e609c7799b9c296046a90b62b570774fd618f5","glsl-optimizer/license.txt":"e26a745226f4a46b3ca00ffbe8be18507362189a2863d04b4f563ba176a9a836","glsl-optimizer/src/compiler/builtin_type_macros.h":"5b4fc4d4da7b07f997b6eb569e37db79fa0735286575ef1fab08d419e76776ff","glsl-optimizer/src/compiler/glsl/README":"66a1c12ed7ba0fb63c55ef4559556d2430b89a394d4a8d057f861b8ee1b42608","glsl-optimizer/src/compiler/glsl/TODO":"dd3b7a098e6f9c85ca8c99ce6dea49d65bb75d4cea243b917f29e4ad2c974603","glsl-optimizer/src/compiler/glsl/ast.h":"97fcbc54c28ad4f73dcbf437bcaaf7466344f05578ed72de6786f6a69897bd4e","glsl-optimizer/src/compiler/glsl/ast_array_index.cpp":"92b4d501f33e0544c00d14e4f8837753afd916c2b42e076ccc95c9e8fc37ba94","glsl-optimizer/src/compiler/glsl/ast_expr.cpp":"afd712a7b1beb2b633888f4a0911b0a8e4ae5eb5ab9c1e3f247d518cdaaa56d6","glsl-optimizer/src/compiler/glsl/ast_function.cpp":"67ec8e47a00773c9048778179c4e32e57b301146a433559a2aec008698f6ca8e","glsl-optimizer/src/compiler/glsl/ast_to_hir.cpp":"4f5fd3b906c0cf79e608b28619e900dbc49ad35e04ccf43e809798d8145d13de","glsl-optimizer/src/compiler/glsl/ast_type.cpp":"8eb790b24b26dfb72bdc333744b566c26d8464c5d47d20eae659461f5c4899f7","glsl-optimizer/src/compiler/glsl/builtin_functions.cpp":"9b153e8e2b8e3721a0e0325507c1745afbe7b0c56c2f3b6997dd74197cb889c8","glsl-optimizer/src/compiler/glsl/builtin_functions.h":"a37cad7ed09b522c5b8bec7b80115a36846e7ba6e0874a2a858e32f7f202c665","glsl-optimizer/src/compiler/glsl/builtin_int64.h":"619def6f3aebf180da3944ef08f159ab12a58b24767e41d8b985ac37ded54d62","glsl-optimizer/src/compiler/glsl/builtin_types.cpp":"afec060b62d6f3b00bfbf94e9fa5f96341ce096c128d1eef322791e6ed9cea4d","glsl-optimizer/src/compiler/glsl/builtin_variables.cpp":"8f033c7a6f3f9a4ca6dac9409cd668e30cc7d618dda6e3aa9451465f9e9f587d","glsl-optimizer/src/compiler/glsl/float64.glsl":"fc60780e102a54d97d091518a3bca12159ff4e23c2fc66a5366b359dfaa9e83b","glsl-optimizer/src/compiler/glsl/generate_ir.cpp":"e5f0175370a0d07f93c48d3f0f1b8233d12c64a7b02de02dcc753ef7b398ef0f","glsl-optimizer/src/compiler/glsl/glcpp/README":"a0332a1b221d047e9cce5181a64d4ac4056046fd878360ec8ae3a7b1e062bcff","glsl-optimizer/src/compiler/glsl/glcpp/glcpp-lex.c":"2d179879b1ffe84f58875eee5b0c19b6bae9c973b0c48e6bcd99978f2f501c80","glsl-optimizer/src/compiler/glsl/glcpp/glcpp-lex.l":"e4c5744c837200dafd7c15a912d13f650308ea552454d4fa67271bc0a5bde118","glsl-optimizer/src/compiler/glsl/glcpp/glcpp-parse.c":"36970dd12f54ed02102fbd57962f00710a70a2effccbcbd6caec7625be486e7b","glsl-optimizer/src/compiler/glsl/glcpp/glcpp-parse.h":"5a7158375ecbf6ac8320466c33d534acbe9e60669f5e1908431851dc1ed1f57f","glsl-optimizer/src/compiler/glsl/glcpp/glcpp-parse.y":"4c9ee9e1fe4e9b96407631e7ec725c96713d1efb1c798538b5e4d02fc8191b9e","glsl-optimizer/src/compiler/glsl/glcpp/glcpp.c":"37ed294403c2abfd17fd999d1ae8d11b170e5e9c878979fefac74a31195c96b0","glsl-optimizer/src/compiler/glsl/glcpp/glcpp.h":"85ac8b444bcbd0822b66448a1da407b6ae5467b649f5afaf5c58325bd7569468","glsl-optimizer/src/compiler/glsl/glcpp/pp.c":"a52d94f1bcb3fb2747a95709c4a77c25de7eea8354d2b83bb18efd96976a4473","glsl-optimizer/src/compiler/glsl/glcpp/pp_standalone_scaffolding.c":"d11aeb3acfe966d1b78f1ee49804093f2434214c41391d139ffcb67b69dc9862","glsl-optimizer/src/compiler/glsl/glcpp/pp_standalone_scaffolding.h":"abbf1f36ec5a92d035bfbb841b9452287d147616e56373cdbee1c0e55af46406","glsl-optimizer/src/compiler/glsl/glsl_lexer.cpp":"272b9fc1383d72b81bfc03fa11fdf82270ed91a294e523f9ce2b4554bd3effa9","glsl-optimizer/src/compiler/glsl/glsl_lexer.ll":"2b57d9f9eb830c3d7961d4533048a158ee6f458c8d05c65bea7b7cfbc36e4458","glsl-optimizer/src/compiler/glsl/glsl_optimizer.cpp":"195487f3d1dca5513712a8c2294f3d684a0e945e6f4e8b7142387f044a5dd7db","glsl-optimizer/src/compiler/glsl/glsl_optimizer.h":"22e843b4ec53ba5f6cd85ca5f7bad33922dca8061b19fb512d46f1caca8d4757","glsl-optimizer/src/compiler/glsl/glsl_parser.cpp":"2a34cbe4afcef6eb0a6a16ea4e920dbad67859cfeefaa1a779991280a5a63e0c","glsl-optimizer/src/compiler/glsl/glsl_parser.h":"a2b79346a0a5b7e75a383f007ac8e07ff85dc12b4ad296d7089e6a01833efec0","glsl-optimizer/src/compiler/glsl/glsl_parser.yy":"91d99418e293cd95dd3ca5c3407b675299904b60de90eb093be248177bdfab3b","glsl-optimizer/src/compiler/glsl/glsl_parser_extras.cpp":"4802ff2208f47849dd6395475e5645e53d696b8cb2ce58e16fb4f86bf9080cb4","glsl-optimizer/src/compiler/glsl/glsl_parser_extras.h":"da52f86890497b7532dd5626f29e1ab12f892ca4d0ade367136f961a9728ffc5","glsl-optimizer/src/compiler/glsl/glsl_symbol_table.cpp":"6660fb83c0ddddbbd64581d46ccfdb9c84bfaa99d13348c289e6442ab00df046","glsl-optimizer/src/compiler/glsl/glsl_symbol_table.h":"24682b8304e0ea3f6318ddb8c859686bd1faee23cd0511d1760977ae975d41bf","glsl-optimizer/src/compiler/glsl/hir_field_selection.cpp":"72a039b0fcab4161788def9e4bedac7ac06a20d8e13146529c6d246bd5202afd","glsl-optimizer/src/compiler/glsl/int64.glsl":"303dbe95dde44b91aee3e38b115b92028400d6a92f9268975d607471984e13eb","glsl-optimizer/src/compiler/glsl/ir.cpp":"0d744d7576e0462fe1db1b7efeff08e7c2b318320a41f47dec70c8e5c7575a25","glsl-optimizer/src/compiler/glsl/ir.h":"e58af2cd704682117173590924f3cec607c2431dcefe005f17d707b734477673","glsl-optimizer/src/compiler/glsl/ir_array_refcount.cpp":"1fde229ea3068d8ef7b9294d294e269931c6dbbcead9a6e7e7cbf36d4a629370","glsl-optimizer/src/compiler/glsl/ir_array_refcount.h":"9ba5f4094805aad4802e406b83bbf7267c14310d0d550b58272d91395349bf1a","glsl-optimizer/src/compiler/glsl/ir_basic_block.cpp":"1e2920b1c0ecb08424c745c558f84d0d7e44b74585cf2cc2265dc4dfede3fa2f","glsl-optimizer/src/compiler/glsl/ir_basic_block.h":"81be7da0fc0ee547cd13ec60c1fcd7d3ce3d70d7e5e988f01a3b43a827acdf05","glsl-optimizer/src/compiler/glsl/ir_builder.cpp":"daba29c5a1efdd5a9754f420eb3e2ebdf73485273497f40d4863dadeddb23c0d","glsl-optimizer/src/compiler/glsl/ir_builder.h":"2822e74dd3f6e3df8b300af27d5b11ea2dd99d0e5e7ca809b7bbcce9833c483c","glsl-optimizer/src/compiler/glsl/ir_builder_print_visitor.cpp":"8c6df5abf2fe313363f285f171c19ca6c8ee4f3bc2ed79d33c0c88cc8be45c48","glsl-optimizer/src/compiler/glsl/ir_builder_print_visitor.h":"799852adc3a0e54d04080655e7cebfa0d3bf5b6ffed5d8414f141380665d4db7","glsl-optimizer/src/compiler/glsl/ir_clone.cpp":"9c2622f3260a120526fb1fdbde70d69de842914e20c29e925373659a2b5c3eaf","glsl-optimizer/src/compiler/glsl/ir_constant_expression.cpp":"21f9d4e2d8e0f423489b18f871e8243472ec79de973ba02ad67b79ce681b492d","glsl-optimizer/src/compiler/glsl/ir_equals.cpp":"bca28533a6310b0fc152b56d80872368f1510dc62ed6e8ac199b9ffa7fac02e7","glsl-optimizer/src/compiler/glsl/ir_expression_flattening.cpp":"7e918d4e1f237eca01396004015865ce345afe32a876c9dbc6728576a1a7eae4","glsl-optimizer/src/compiler/glsl/ir_expression_flattening.h":"f45b66aa9497520e7e08e612d24b308477c34477fbd963ee9320eac664957f16","glsl-optimizer/src/compiler/glsl/ir_expression_operation.h":"d8a94147da73b169a99c95378eecc0570983e1805ad201a773ff1a42d5d50a24","glsl-optimizer/src/compiler/glsl/ir_expression_operation.py":"38bafed32b98ff492cc611514160a39c2e6e17d198b5d290b5727bcd4b55aee1","glsl-optimizer/src/compiler/glsl/ir_expression_operation_constant.h":"8c751e72df480d5c012ebe0ebe25209464b1af32c23e199e4552169c425c7678","glsl-optimizer/src/compiler/glsl/ir_expression_operation_strings.h":"fc9251dcab8e73e00ffc983da3ead3cf32c160eaec1111e23b45eff6f9f4f37e","glsl-optimizer/src/compiler/glsl/ir_function.cpp":"7537365fc0fbe4b37a26b9a2146cc64d3e9a774d60eab63b65002ad165ae8fc7","glsl-optimizer/src/compiler/glsl/ir_function_can_inline.cpp":"faddbf112187a048d502716a3fb82570a322299ba2a3abd79388382c82040bfc","glsl-optimizer/src/compiler/glsl/ir_function_detect_recursion.cpp":"9176973eaf5c0a984701f953bb7a80f37dca43d59b5bce50fc69b3f02f2902d7","glsl-optimizer/src/compiler/glsl/ir_function_inlining.h":"9739493f99c489987d650762fccdd3fb3d432f6481d67f6c799176685bd59632","glsl-optimizer/src/compiler/glsl/ir_hierarchical_visitor.cpp":"c0adaa39f0a94e2c2e7cee2f181043c1fd5d35849fef1a806c62967586a4c3ca","glsl-optimizer/src/compiler/glsl/ir_hierarchical_visitor.h":"0bfe80bbbf9b0f4ae000a333df77fb1cd144a8cda11c29b54c1eabf96f2c351d","glsl-optimizer/src/compiler/glsl/ir_hv_accept.cpp":"caf7ce2cd9494aadd3c58bcf77f29de58368dc9e347a362bbf37f8bda9509b80","glsl-optimizer/src/compiler/glsl/ir_optimization.h":"cd394c803199d96e23a1c9e3f5d2758a5d6645a56c7ec8bd7fe0a6bbe0808351","glsl-optimizer/src/compiler/glsl/ir_print_glsl_visitor.cpp":"1ee46cca6c3562c018614412181c02faf494c92c07d2c7b345d19b355e9b52f3","glsl-optimizer/src/compiler/glsl/ir_print_glsl_visitor.h":"1ad1bd3efd1ace39051c13f904c05fd80425d329444f9a8d47fd6d948faf46e0","glsl-optimizer/src/compiler/glsl/ir_print_visitor.cpp":"066c65b8e181d962ee913388b69c7941362685b66ffe1758abd31b384a96934a","glsl-optimizer/src/compiler/glsl/ir_print_visitor.h":"4573eb93268a2654c14b505253dd651e2695d43dc745904d824da18305269b95","glsl-optimizer/src/compiler/glsl/ir_reader.cpp":"06bfba802c8354e5a8b2334b6d78d6297de18235bedd3f8fbb382c89870b02f2","glsl-optimizer/src/compiler/glsl/ir_reader.h":"63e3f7f1597936a7011d5b520e171b197bf82bee6c1560d822c3edf5aaa6f9e9","glsl-optimizer/src/compiler/glsl/ir_rvalue_visitor.cpp":"84b5c5d746555adca85759c2912fe48010232b7c1c0bd2cf03bd04067a85e66f","glsl-optimizer/src/compiler/glsl/ir_rvalue_visitor.h":"fd8c561b71085d3211fff85ed514fecb299d8ce19a04bc063419a55b6d840525","glsl-optimizer/src/compiler/glsl/ir_set_program_inouts.cpp":"ab9f115ce9e7f312d9c7978340ced0dc4ae6d13a80e08442ba9709d11d50cae5","glsl-optimizer/src/compiler/glsl/ir_uniform.h":"683ae6896b1a08470c090be5f822fc31cd434eab9216e954b9bba24a46975109","glsl-optimizer/src/compiler/glsl/ir_unused_structs.cpp":"15d27cd5ef2748922b8341d7887e6c5bc6d1f4801c36d25c769e48d364342398","glsl-optimizer/src/compiler/glsl/ir_unused_structs.h":"13387b49c23093575276b25b9dfd31fedd8f131c5c4f3128ab04cf03e15b5295","glsl-optimizer/src/compiler/glsl/ir_validate.cpp":"bded6922c63173e7cb15882bd7fd0e25b9a478c4223fc0ffcfd0890d137f4ed1","glsl-optimizer/src/compiler/glsl/ir_variable_refcount.cpp":"2764a3cad937d53f36db7447c3a5b98b04bf153acf81074d971857fc5bca460d","glsl-optimizer/src/compiler/glsl/ir_variable_refcount.h":"b0668e3eb1501ef65e38fe12830742ecb3d28e6039f30e366c8924efc29b4a39","glsl-optimizer/src/compiler/glsl/ir_visitor.h":"f21b3534c3d66d5fb707d1581fece7e1eb043523afbaedf89918cfb031c6df94","glsl-optimizer/src/compiler/glsl/link_atomics.cpp":"360f0209e11f367ba358223597b0a118bae095bff16337cf03f1fb89c5b80ca6","glsl-optimizer/src/compiler/glsl/link_functions.cpp":"de7895da8aa33a1e3c2c1eb2fdaf267ab5d1fbfdb79ae2e67f95211e946e294c","glsl-optimizer/src/compiler/glsl/link_interface_blocks.cpp":"1926cfa73810704eb19b916c1b2cdb9321155e2f98b2a0a57c7c3c6e960540cd","glsl-optimizer/src/compiler/glsl/link_uniform_block_active_visitor.cpp":"1e14e06ca3b2c1089cfba2e8eaf0c1f373d9d6374b6082f320962dd71ae09611","glsl-optimizer/src/compiler/glsl/link_uniform_block_active_visitor.h":"fd58c155af645295bb6aec08797889de586f4d919731de2bce57e8dce59bb048","glsl-optimizer/src/compiler/glsl/link_uniform_blocks.cpp":"09589f49776dce32e6c4044937de7e0c839a9754ad31960148f8f9e010658997","glsl-optimizer/src/compiler/glsl/link_uniform_initializers.cpp":"bf98e08c12db466acf9623cbeb8fa8e3b4002512722e7a6521287f558a099f37","glsl-optimizer/src/compiler/glsl/link_uniforms.cpp":"84bad5b1377362cecf259b05124239be5220b03ce1c0c61b59bd9a47e4379af2","glsl-optimizer/src/compiler/glsl/link_varyings.cpp":"09e6a9395f142d6029e8d58cd993685f2bed35125d193a39bc7c96ec6ebed6f8","glsl-optimizer/src/compiler/glsl/link_varyings.h":"44a1270f8ed61cab8481358c7342943958618bb5057cd342369373b79c74abd0","glsl-optimizer/src/compiler/glsl/linker.cpp":"dcfbfab55f31c81afc90aec7d0a1620a80a4a9eea642efb20a99eaafc32ba95b","glsl-optimizer/src/compiler/glsl/linker.h":"ecf94b4ad75ef461c27c557fda4bd25f34c91930822b8e1d729ec84520d4a049","glsl-optimizer/src/compiler/glsl/linker_util.cpp":"6bef0fd8438c4de02140e93e1af6855e56f7aed6f9dbcb820e54bbaa4ae0eb6c","glsl-optimizer/src/compiler/glsl/linker_util.h":"462a266538ba9812f96ac9226519ba3b2e54ff794adee60c143e8676c5c047d8","glsl-optimizer/src/compiler/glsl/list.h":"8fffadc41788723420e6b4c1c19b6e400682fe72d458f4a0aedcb600b9404dfb","glsl-optimizer/src/compiler/glsl/loop_analysis.cpp":"57ecd573477c68091c7cc99537faa7139a8f395935e3d4f10144cefdefb5a611","glsl-optimizer/src/compiler/glsl/loop_analysis.h":"a85f045a038ee5b5176063e85d7988865862c44ab0580f771b993a042d0b69cc","glsl-optimizer/src/compiler/glsl/loop_unroll.cpp":"bd4292ea2809f5a669bcb76ceaa1ac365772dcd638c579c3ed10275214901a54","glsl-optimizer/src/compiler/glsl/lower_blend_equation_advanced.cpp":"8cfbef140d9c4b4d2f57bfa05c9c374d31a121d0f87afce94333f049023b654a","glsl-optimizer/src/compiler/glsl/lower_buffer_access.cpp":"1ae221c3c7a95aeb867207e7a742be635f91b406c157747bfd6ddf10274d97fb","glsl-optimizer/src/compiler/glsl/lower_buffer_access.h":"807886953a576a323591798cbca5e2df24295ea893b28affd8ffb5926cebaa04","glsl-optimizer/src/compiler/glsl/lower_const_arrays_to_uniforms.cpp":"608403f0eeeedf21cfcd3014116e0f44e28cbdf6c4c32aac7e613e64e30205e1","glsl-optimizer/src/compiler/glsl/lower_cs_derived.cpp":"179905cd47a294122adeb5b0abfed6f2f67782dcde21b544d1ee2c1985154e66","glsl-optimizer/src/compiler/glsl/lower_discard.cpp":"3b361b2db0004d544d64611cb50d5a6e364cf6c5f2e60c449085d7d753dd7fb0","glsl-optimizer/src/compiler/glsl/lower_discard_flow.cpp":"f5c29b6a27690bb5c91f196d1a1cf9f6be4f1025292311fe2dac561ce6774dee","glsl-optimizer/src/compiler/glsl/lower_distance.cpp":"a118c85493d5d22b2c059a930c51a5854896d4b1dade76598eaa985e5a3dff8c","glsl-optimizer/src/compiler/glsl/lower_if_to_cond_assign.cpp":"469e617757fd1728709cce021aac5c8da05ee503bf5366977bdc4ef7a6d83950","glsl-optimizer/src/compiler/glsl/lower_instructions.cpp":"39dc7589b56758884cb322287d8bb8cd81d3bd8986fadc9fd4d68bf422b1f281","glsl-optimizer/src/compiler/glsl/lower_int64.cpp":"d1ed41196880dd53c7b13e2782f9423f8442bf1d46186e8be92b1b66218a83ee","glsl-optimizer/src/compiler/glsl/lower_jumps.cpp":"f638ef8eaec462bc2ce4b1874f59c66aeed24774dfdd7e9fe2b5eab7206e4524","glsl-optimizer/src/compiler/glsl/lower_mat_op_to_vec.cpp":"33d55d38cbe4af8e345765214303d5ace282e024992e7a9420f4338b9a4d1e34","glsl-optimizer/src/compiler/glsl/lower_named_interface_blocks.cpp":"16063ac127bff75a68272070ab11c21c25101edbff62b4c68f4983b4cd941af0","glsl-optimizer/src/compiler/glsl/lower_noise.cpp":"cfdf639cdf5a1f76a7a73234e1bf0c72e5d2089cac44a6663c2012b7f99431af","glsl-optimizer/src/compiler/glsl/lower_offset_array.cpp":"3b00773399135aea85746a5a68b96ef000bc6841be1a2c8e6f25c516628b0949","glsl-optimizer/src/compiler/glsl/lower_output_reads.cpp":"a0fc9975d5aa1617e21fc6c353659a9802da9e83779a3eef4ec584f74b4dadc5","glsl-optimizer/src/compiler/glsl/lower_packed_varyings.cpp":"2cfecd9e8e12603ce8038db74c9dac0dcb7fb77f6ec34baf76896dc235e214bd","glsl-optimizer/src/compiler/glsl/lower_packing_builtins.cpp":"79a13d161fe505a410ab948d92769395708693ec888153630fa240e5b97e356f","glsl-optimizer/src/compiler/glsl/lower_shared_reference.cpp":"ea2dccf50a83bc19391bf6b7ab6aa53c0005f427af4066d25140340af9a4beef","glsl-optimizer/src/compiler/glsl/lower_subroutine.cpp":"f69fa53650eeb6f2944fce4d36a6e0a423e6705f3a3bd3389c7fadb83cfc8802","glsl-optimizer/src/compiler/glsl/lower_tess_level.cpp":"b196c9d424c0569f3e85d75c2d125af21566cb113d69036db87c0990703e0fa7","glsl-optimizer/src/compiler/glsl/lower_texture_projection.cpp":"4d247f244272adc8250fd888d8d932a140dd5de4d1efc7a58492c3c2b8291527","glsl-optimizer/src/compiler/glsl/lower_ubo_reference.cpp":"89bdbc6c1669230c644c0857db1ce2781ec61d349ecd08c7914146e1f4750a4a","glsl-optimizer/src/compiler/glsl/lower_variable_index_to_cond_assign.cpp":"fce930f29ac9405b297d1f749d68f59506b89c70b4ee1b1ab8cf49a34cc71ecf","glsl-optimizer/src/compiler/glsl/lower_vec_index_to_cond_assign.cpp":"3c67d851a11a55fad1c49a550f3a0cfe50892d33a3f238ce266cd829eba510a8","glsl-optimizer/src/compiler/glsl/lower_vec_index_to_swizzle.cpp":"f5ec666b73e1415cbab32519a53605ed385f3b03e889560373dbce69dda5000e","glsl-optimizer/src/compiler/glsl/lower_vector.cpp":"f7c13f5572ebe09b6a71553133b2cf003cd4b77b9657600672ee3b21bf890725","glsl-optimizer/src/compiler/glsl/lower_vector_derefs.cpp":"b05793da6dd620a531b43df5af8b2ecbc37b9db0c88910f5724ea10bcd057e19","glsl-optimizer/src/compiler/glsl/lower_vector_insert.cpp":"fee772ec17eea5e86a529bf9c5fa2ee0d29a5982bb75ebc6d68ed36cd19aa299","glsl-optimizer/src/compiler/glsl/lower_vertex_id.cpp":"690e8715182e03fead5cc5a35251fb4f41b357e4c71a1dfbc4bd7be19862b56d","glsl-optimizer/src/compiler/glsl/main.cpp":"d9d3841884a388a57e0adcd6b830ea59fb3fb7c5d78f2c0796f11d4ce3c9f96a","glsl-optimizer/src/compiler/glsl/opt_add_neg_to_sub.h":"f5054944bfd068810629080d0ea11df78b3f57a8f86df75e13ca50157ad1964d","glsl-optimizer/src/compiler/glsl/opt_algebraic.cpp":"121d58ee9dd11e3fffca31d8a1a3f3abcf80aed174a2c740986bbd81cdeb0e6d","glsl-optimizer/src/compiler/glsl/opt_array_splitting.cpp":"19d3ce0e815438f4df9ab2890e767b03a4f3f191b53bb30c0217cf2ae6a95430","glsl-optimizer/src/compiler/glsl/opt_conditional_discard.cpp":"0e44e0e126711a3725c1f3a2aa65ff03c381fed08680ffc30101aae60f716c4e","glsl-optimizer/src/compiler/glsl/opt_constant_folding.cpp":"a088d04d9b45f9e55e235835648f614c89b7803c03a6d4f6a6d1a6bc1f0228bd","glsl-optimizer/src/compiler/glsl/opt_constant_propagation.cpp":"710109a6249858e7cf764dbbf695836e0fe421f8a651e067fb989974e7b474ff","glsl-optimizer/src/compiler/glsl/opt_constant_variable.cpp":"4a395474e9a8aa45b84b6b683c7783791400a30e75a6814d3fbb722d85c12aa2","glsl-optimizer/src/compiler/glsl/opt_copy_propagation_elements.cpp":"ffa0f50863995e0d2e31f55a52e82319edc71e520987bebd7f7e561ea331c64b","glsl-optimizer/src/compiler/glsl/opt_dead_builtin_variables.cpp":"84e8747b948232f01dd56b428b9315f96f9511f605f240119fc446fae28981a9","glsl-optimizer/src/compiler/glsl/opt_dead_builtin_varyings.cpp":"761523e88f5b3ba785170f4d7205e94fa99acb7e74d29efbe40e1c010e1dbdb3","glsl-optimizer/src/compiler/glsl/opt_dead_code.cpp":"fd1ba2da7337d4e5dad17f5c2d73d9cc8880305f423e85d64cf94553588fa401","glsl-optimizer/src/compiler/glsl/opt_dead_code_local.cpp":"bfc0b6d5a42d80c9c6b57130d3322b6940b4a02021488f4aeef489b2c3652a7a","glsl-optimizer/src/compiler/glsl/opt_dead_functions.cpp":"774cae6536d02edf26e996a2a895e1f62d5098f16dc96b44798b4fc731a9a95f","glsl-optimizer/src/compiler/glsl/opt_flatten_nested_if_blocks.cpp":"3696a5c55f02e20056e085bc2714f73ac992f221b6f3387d655068e86b512046","glsl-optimizer/src/compiler/glsl/opt_flip_matrices.cpp":"44f0fe05b49329667671f88c96dc86ab3fe1459ff7b87f2b2d88de2d49829f9f","glsl-optimizer/src/compiler/glsl/opt_function_inlining.cpp":"fb56a33c90419a01676b57cbd91d0674a54cca40e6defaacc88dd33facebc131","glsl-optimizer/src/compiler/glsl/opt_if_simplification.cpp":"ac406eb35e379c357641d6c5749f50c65961455924d3dc884e2b90046fa92c5c","glsl-optimizer/src/compiler/glsl/opt_minmax.cpp":"27c6c5357043b5c6e5d594d7476e9a00e8f6db033a86f5c984243f44ed492430","glsl-optimizer/src/compiler/glsl/opt_rebalance_tree.cpp":"8bb6329dc0f299042368fc81934c2df019b45ab9f7aa0415d4e57b8d1ff98c9f","glsl-optimizer/src/compiler/glsl/opt_redundant_jumps.cpp":"222c73e2ac7a938ebb6428cc6c780c908ff6156d8ff935b04fed93a48fc10496","glsl-optimizer/src/compiler/glsl/opt_structure_splitting.cpp":"2edc79cc13f3177934e0443ad62f5976a1991f01f86ea303a803434849b13a47","glsl-optimizer/src/compiler/glsl/opt_swizzle.cpp":"015d0abddfe507f67c4b96c82988d861d018ededf7bf055e2bcbe9ea92da694e","glsl-optimizer/src/compiler/glsl/opt_tree_grafting.cpp":"46d28ac983ea244a4315bdc0e8892979ec4d1f9b9a96ac8a8a08006d9bc5e878","glsl-optimizer/src/compiler/glsl/opt_vectorize.cpp":"d80ee43bb97d9f016fb9c5e1e06f5b2afa569811f368ba067be794ec11d085fb","glsl-optimizer/src/compiler/glsl/program.h":"2982447e2abd35371e273ad87951722782a8b21c08294f67c39d987da1e1c55f","glsl-optimizer/src/compiler/glsl/propagate_invariance.cpp":"080943e21baa32494723a2eefb185915d2daae1f46d6df420145c5ad6857e119","glsl-optimizer/src/compiler/glsl/s_expression.cpp":"1ced972bc6ecc8eab4116ea71fb0212ab9ae5bcc0be3b47aa5d9d903566b3af1","glsl-optimizer/src/compiler/glsl/s_expression.h":"65b847e30e22a809b57d0bc70243049c99d9c6318803c5b8d0826aba55dc217e","glsl-optimizer/src/compiler/glsl/serialize.cpp":"d57addf5e72954a98192a09287f5013a86a802b763112ab88b6595a356384864","glsl-optimizer/src/compiler/glsl/serialize.h":"57425732eba1233d928e5f07f88b623ce65af46b3bb034bf147f0a4b7f94f9a1","glsl-optimizer/src/compiler/glsl/shader_cache.cpp":"e0c5c433f2df3fccdf1d61281bfcb0ee5633433339b97c697d64db99611cbaaf","glsl-optimizer/src/compiler/glsl/shader_cache.h":"9217164d8d7f54aca0fe5922c7187095a6ae0cb703b196b79805aeef07a7e697","glsl-optimizer/src/compiler/glsl/standalone.cpp":"37e5566b2a20ab8a9f2262735a37598482816abec3e348221d8d95c5a2762aa1","glsl-optimizer/src/compiler/glsl/standalone.h":"788d6a39b6b93a7ed6eafa2c8f9c439ac84aeddb7545f3d4381af29bd93aaa2e","glsl-optimizer/src/compiler/glsl/standalone_scaffolding.cpp":"f71ba2958c75f1504ea6ef56d6ccdc3c0ea291cac38513978fa0b8bee1595e96","glsl-optimizer/src/compiler/glsl/standalone_scaffolding.h":"d921a617ea82b9e49413314492a645c44356de503581b1be3f1b57de236e480d","glsl-optimizer/src/compiler/glsl/string_to_uint_map.cpp":"d824bf5b839bd39498dc9e457103cdbe3e5289ddf7564107c27b1505948dd31f","glsl-optimizer/src/compiler/glsl/string_to_uint_map.h":"e2f18e66359c9d620e085de7f4a334a47df9c66e65a5bfe8b734c627bec04104","glsl-optimizer/src/compiler/glsl/test_optpass.h":"b27b8f35f5387e7ce4982bb51c7b63ccf14f91757f3108a5d02ed006925bb8a0","glsl-optimizer/src/compiler/glsl/xxd.py":"376484142f27f45090ea8203ae2621abf73f06175cb0ee8d96f44a3b9327f4bd","glsl-optimizer/src/compiler/glsl_types.cpp":"61664f65ecf47c9787f71020050bcef67215afe2885b9b4656bbd2f9b2b575b5","glsl-optimizer/src/compiler/glsl_types.h":"3c9f573559192c1c339af967cd65224be54c9e05cc4758b2ffac9b0b7485c88f","glsl-optimizer/src/compiler/shader_enums.c":"f97a3b1b07ef70b387e540b538af8073fe5f7ffb591515e3abf913acdd7f34bc","glsl-optimizer/src/compiler/shader_enums.h":"9681494cb850bd4ccd1fd18471af00456d68122dcc40a916fb061c6d6ed4854a","glsl-optimizer/src/compiler/shader_info.h":"457bdf6409ab07a154ef172c65380d4973e7cb11d14d36a6d7b3b7c66e2edd2f","glsl-optimizer/src/gallium/auxiliary/util/u_half.h":"a4e2ddd24cf9a1e04f18765dbc29d5acf1a3f71da77a91b034fd0e3a7d047268","glsl-optimizer/src/gallium/include/pipe/p_compiler.h":"587317125c88baa3a562fa9a1985f905a2f47922af29d23b86b78117d08790b4","glsl-optimizer/src/gallium/include/pipe/p_config.h":"a27692fc35f9e55df3224b7529e66b3001e911e94e6bc5f8f569e493e1ee3fb7","glsl-optimizer/src/gallium/include/pipe/p_format.h":"d15e7fbe83174e0e0122e25a1720dda487cbe5776b764ce71055512922088f10","glsl-optimizer/src/mapi/glapi/glapi.h":"73632a625c0ddabc401205e8b5a81eb8af8506868efe4b170d7979ec3619e9c5","glsl-optimizer/src/mesa/main/compiler.h":"79e3bf40a5bab704e6c949f23a1352759607bb57d80e5d8df2ef159755f10b68","glsl-optimizer/src/mesa/main/config.h":"5800259373099e5405de2eb52619f9de242552a479902a3a642a333c8cb3c1e7","glsl-optimizer/src/mesa/main/context.c":"02c18b693312dc50129d66e353220df736cba58a0faaa38316d861025441e78a","glsl-optimizer/src/mesa/main/context.h":"407bddf4a338a0a65f9317e3d076910502d43c948c8a6b7e700e55212fdc155b","glsl-optimizer/src/mesa/main/dd.h":"845ead03db94fab79c7b8e3155bb9c795d1a91b10857a745afc666046e077e4f","glsl-optimizer/src/mesa/main/debug_output.h":"7312422e90b8c0e34028ac27280e438139b5cba525c99deb3ac883cd3d87e452","glsl-optimizer/src/mesa/main/draw.h":"3f5fea0fe2fc5e6fa8db4f4db2481a5d2c683a500ac290d946b063ddf579fd74","glsl-optimizer/src/mesa/main/enums.h":"87d562a6764f51c014a2274fa7c3aca17c04441537ddd56b2554f13c6fffea92","glsl-optimizer/src/mesa/main/errors.h":"c79444b5df289c90fbb22a33b2d0c23917d9fc4510960088f0b79e53bb56b1b2","glsl-optimizer/src/mesa/main/extensions.h":"483fe6654938ce1c8e8ded5dde2eefd2710fcf4dade37fb9c8d08c128f362113","glsl-optimizer/src/mesa/main/extensions_table.c":"17642d1a8c9a0bf2bd61060052d33ff14a005d2b962e6cf91465797a50851e85","glsl-optimizer/src/mesa/main/extensions_table.h":"d78d97a1df035a9d7562cec0cc6feadf79888b2eebc79336f3eb3e73321ee2ce","glsl-optimizer/src/mesa/main/formats.h":"a45bb586e2f990b906e605b7233c51389e72dfa7cd33fb220f21d78c4edcd18e","glsl-optimizer/src/mesa/main/glheader.h":"58217b33eead6aa6b23cd4a291cefeaa6cb84e465f4960daffca97c44d6d1c35","glsl-optimizer/src/mesa/main/hash.h":"5ea00760025c688cf81ba25cb99ebcfcd2c79091d44fc5b6257b4876d11ea04e","glsl-optimizer/src/mesa/main/imports.c":"c102235731498dfb7204f753c9e650daaf9e4609ba5d85aafdaca994c7b88325","glsl-optimizer/src/mesa/main/imports.h":"31634703de1e30bc3e40d63dac4055ae025a608ceaf3c9da5d64c8c5e9a31fb2","glsl-optimizer/src/mesa/main/macros.h":"fc04dd953826c9ff1b2850fbeaa2a6c59c964450b4923f52e3425e7c4f58b085","glsl-optimizer/src/mesa/main/menums.h":"5dfac0e2279d60b0cd0c7b9fc2a5021620d0f6282ed2e738c420214e3af152d3","glsl-optimizer/src/mesa/main/mtypes.h":"69eebf3ed20da8042fce544f92ad81454234d5968e6f9a9c4db38184fefbad3f","glsl-optimizer/src/mesa/main/shaderobj.h":"9f0dfe96d0c2154201adef942bd36053533ac7b2492fb3786acda5bea514c75e","glsl-optimizer/src/mesa/main/uniforms.h":"4e331e6ad6e9cbded978b4082dbe0a57c1f8f01327446bb6892bfc179976c38b","glsl-optimizer/src/mesa/main/version.h":"9d0a13a758099302dc55cf7d045791834a89b0f9d4cf17b2692259b369a8a9a1","glsl-optimizer/src/mesa/math/m_matrix.h":"a37b19f182e070db3df93b0ede43c22fb8be8c2906504133ee6dbd7db1185d8b","glsl-optimizer/src/mesa/program/dummy_errors.c":"1820e305515b4c5e041f5e1623266a48ec8f076a155310be7d60637101f593e4","glsl-optimizer/src/mesa/program/ir_to_mesa.h":"b47f58d22e3ca2ae42d52501ea769d15c4476834944fa97eeccd3a3439211d00","glsl-optimizer/src/mesa/program/prog_instruction.h":"ab3832152a7e144b59e5a2264b2c29db56d93be31e76bbd958527a56771b40eb","glsl-optimizer/src/mesa/program/prog_parameter.h":"2211768d6458b21f84c3a58083a92efe52a9902ece92a23ee83184c3a3a2e16a","glsl-optimizer/src/mesa/program/prog_statevars.h":"fc413698f84bc52d45fdeae0471934ee9904bfb7eac1a2b5f70446e54bcbbdca","glsl-optimizer/src/mesa/program/program.h":"f61c9d123f28c7ff8b390648d35f329e7b6e68e33823239d539b7be8384541bb","glsl-optimizer/src/mesa/program/symbol_table.c":"f275a98f1afc91399a14dbbc5a9d222bdf6e21764c7b83ec688962b40caece91","glsl-optimizer/src/mesa/program/symbol_table.h":"631dc35ac48d5e87962d45507461920f6575610960ffcc42a08cefeb43300cda","glsl-optimizer/src/mesa/vbo/vbo.h":"b9bf5ad54267cfd7af2e842dda029090dcc7db1c5b7825914736c3c132909d95","glsl-optimizer/src/util/bitscan.h":"d4fcb47b57a50d70cb97f99ca3e619bc06282a877768a435e009775ce8d77f36","glsl-optimizer/src/util/bitset.h":"c40f78515c6230fed18345c6751ce33833a49da7a27901c7e6d7340cbdcbc5e7","glsl-optimizer/src/util/blob.c":"214fea1499bc25eed6eb560651f3358cadbaf507b4ec8bdb8f894c13010ab3f5","glsl-optimizer/src/util/blob.h":"093d5dc1acbd424eaaf8e48d6735d4c4acf8d5d48d7226fa21c249e32f0108aa","glsl-optimizer/src/util/crc32.c":"2f3467a046b3a76784ecb9aa55d527698c8607fd0b12c622f6691aaa77b58505","glsl-optimizer/src/util/crc32.h":"59bd81865e51042b73a86f8fb117c312418df095fed2d828c5c1d1c8b6fc6cd4","glsl-optimizer/src/util/debug.c":"4e307954f49d9700a99510684f930a8e404c8e1078f5a774f9245711e963fe9a","glsl-optimizer/src/util/debug.h":"50068d745c4199ccbd33d68dd4c8a36d2b5179c7869a21e75906ddd0718ca456","glsl-optimizer/src/util/detect_os.h":"343a8790d17a3710c6dd015ee367f84e3902ff3f2e36faca2bf93f9d725d3574","glsl-optimizer/src/util/disk_cache.c":"c963a961597ce5c1de98424f38b3a4163c8479410539bbe1bc142c06b2b5e1d1","glsl-optimizer/src/util/disk_cache.h":"e83314fb14134a8e079b15e470a6376ba5a8253701f048c890a62b7e55d64bc8","glsl-optimizer/src/util/fast_urem_by_const.h":"e108fce804616c47d071dfe4a04163eec1126e448ed1aa89abb6b3a6d772bd5b","glsl-optimizer/src/util/fnv1a.h":"ab2596f19c6adf431ae27618f62c5743e24ad23ef83bb359a4c4c218245ab459","glsl-optimizer/src/util/futex.h":"fae18b3385e7bd683e06c399aae64428c92133bb808e5c04d957dfea0c466910","glsl-optimizer/src/util/half_float.c":"11bc2584493d5d9d46e8c8a619a0307cf150bf5ab5d0f96bb764b061dc37a00e","glsl-optimizer/src/util/half_float.h":"698a6d628c38244ef816cf69dda6e3cc7341725956e990bddde11a11e2565330","glsl-optimizer/src/util/hash_table.c":"f8b81f85ae418f9ee5b077bdbfafde708325357bcbb75cb04924316d629c7a8f","glsl-optimizer/src/util/hash_table.h":"217191bb360592e2232f187473c10287d2cda8ae6fa5c53d0ef74c8c206118b4","glsl-optimizer/src/util/list.h":"9fab03c6a78186bb5f173269f825f6ce976b409d931852e3d93bac632e07989a","glsl-optimizer/src/util/macros.h":"5057bb77c9ffec4ccdb4fb4640dd6eb05caf549e8665ea4afb5ba1142a4a5a17","glsl-optimizer/src/util/mesa-sha1.c":"00c692ec353ebc02c06c57c5a71de0ab7a119f86a4146f452e65ec87e4944417","glsl-optimizer/src/util/mesa-sha1.h":"bff4c29f4bf7cdbcefb30fa0c996a7604a380eba8976467c2a60e7cd328f7e26","glsl-optimizer/src/util/mesa-sha1_test.c":"25da89a59d51469f77b4c468ca23ffdce0a7a1166a70b6cc23026a6800b0143c","glsl-optimizer/src/util/ralloc.c":"691183679ceb2f1e0fbfe0669f5accd239ceb3449df7586c7269b011765fdc35","glsl-optimizer/src/util/ralloc.h":"e573c45875ff1530f0dbee9a93ae55535fdac8d5cc88a79ebc327c688824bde5","glsl-optimizer/src/util/rounding.h":"bee6e21354e569c58f0b34a34351903394f6ad890391dd9c8025a399891912e1","glsl-optimizer/src/util/set.c":"a71293beff2fc7da6ca4118f89e8758d024571049207db3d2491084cafa8a3a5","glsl-optimizer/src/util/set.h":"3e39ca161e7ed4ec7c436cc9c7919ed9a55ed1b71edbf2caf6f9bcfd9bc578ed","glsl-optimizer/src/util/sha1/README":"00af7419af05247081858acb2902efd99fcda2ce16e331079f701645bb3729c0","glsl-optimizer/src/util/sha1/sha1.c":"1403bbe0aad42ba3e6be7e09f7cad87a6a8c4ad5b63962f7b92b9f37d8133b04","glsl-optimizer/src/util/sha1/sha1.h":"68d9f240eab2918026ecdf22be36811abbd4f1389f6c36e31258041aeaedd247","glsl-optimizer/src/util/simple_mtx.h":"46dcc6a53a682cacd1e093950d37b2f2715865bc88c030ae8120ec76907578e2","glsl-optimizer/src/util/softfloat.c":"a97e51a96fe5e6a052c02aa6bbec683fe73fb88a8c087d9c930503e2120d8a2e","glsl-optimizer/src/util/softfloat.h":"66664b0250e83bf5dd4cc743acd119d076efcea624a0eab3d6b60718e6ee8811","glsl-optimizer/src/util/string_buffer.c":"63a1d1b1e34926c88ea00159cafbcd56568b805c4f64d1e8c97169fe313921fc","glsl-optimizer/src/util/string_buffer.h":"7b88d1b1d9c6cfb8e93331813535c127289437c75f822029e9a3bca8ea6b52ee","glsl-optimizer/src/util/strndup.h":"0273c4fdb7482cd7746881a63d3998648c6d63415ba85af1d1860f0e0dc504c6","glsl-optimizer/src/util/strtod.c":"5cf610d8a37373cf37cfb7aae903525d943b2674b1f32594c70b0eb19a8c9697","glsl-optimizer/src/util/strtod.h":"237396def4e264d35ed4bedea00ef9a4ceab6d7a11a18c770d9747d22c69ed2d","glsl-optimizer/src/util/u_atomic.h":"c02e809526c6c09ba8fe51f50b2490d1b6c8e5c7f3c4031ae958250d098fc3bb","glsl-optimizer/src/util/u_dynarray.h":"853d0fa6ff2261614488be624deb8a2b01e57c2c8eabc28578cbeed4ccc95694","glsl-optimizer/src/util/u_endian.h":"3ccea7e529740318d8a4b05c00db3adc9d1e292a52bdc56a05c9fae99209720f","glsl-optimizer/src/util/u_math.c":"c868a8c0886dc78f1b06b13404ba8b253090449045774dd56893ac9d75795184","glsl-optimizer/src/util/u_math.h":"57e7411c1afc06c43c1f087dc8de9ffe99ee0a67d28d40d8a87489aecffa9a0e","glsl-optimizer/src/util/u_string.h":"8bbc5f0d81cd482bf0aa201e95eb1c6ab3d6dfcb47c1c440e0c2fe5730cee14d","glsl-optimizer/src/util/xxhash.h":"2f2aff2fc6c0c929f52cf6ae7314122124c5be026d41ad1c357608383c4a37ad","src/bindings.rs":"79993db2058bde39f99ef483d02560d33b1cb882f6a552319e8b86eb6f9021e1","src/lib.rs":"04be1554cd829eb40864b06d80b491dd48117a4e3a601c7d482117f7a0391e67","wrapper.hpp":"f3ea34cc496f7d90b9bfcada3250b37b314c3524dac693b2ece9517bc7d274ac"},"package":"f22b383fcf6f85c4a268af39a0758ec40970e5f9f8fe9809e4415d48409b8379"}
\ No newline at end of file
EOF
