# GNU/Linux Distro Installer

This is a collection of shell functions to build secure Linux-based operating system images.  I am writing this project in an attempt to automate and unify a lot of the things I would do manually when installing systems, as well as to cross-compile images from fast modern hardware tuned for old embedded chips and uncommon CPU architectures.

## About

The primary goal here is interchangeable immutable disk images that are verified by verity, which is itself verified by the kernel's Secure Boot signature on UEFI platforms.  This script creates a container to run the build procedure which outputs components of an installed operating system (such as the root file system image, kernel, initrd, etc.) that can be assembled as desired, but my testing focuses on three main use cases:

 1. A system's bootable hard drive is GPT-partitioned with an ESP, several partitions reserved to store root file system images, and the rest of the disk used as encrypted partitions for persistent storage.  A signed UEFI executable corresponding to each active root file system partition is written to the ESP so that each image can be booted interchangeably with zero configuration.  This allows easily installing updated images or migrating to different software.

    Example installation: `bash -x install.sh -E /boot/EFI/BOOT/BOOTX64.EFI -IP e08ede5f-56d4-4d6d-b8d9-abf7ef5be608 examples/systems/desktop-fedora.sh`

 2. The installer produces a single UEFI executable that has the entire root file system image bundled into it.  Such a file can be booted on any machine from a USB key, via PXE, or just from a regular hard drive's ESP as a rescue system.

    Example installation: `bash -x install.sh -KSE /boot/EFI/BOOT/RESCUE.EFI -a admin::wheel -p 'cryptsetup dosfstools e2fsprogs kbd kernel-modules-extra lvm2 man-db man-pages sudo vim-minimal'`

 3. All boot-related functionality is omitted, so a file system image is created that can be used as a container.

    Example installation: `bash -x install.sh examples/containers/VVVVVV.sh`

The installer can produce an executable disk image for testing each of these configurations if a command to launch a container or virtual machine is specified.

## Usage

The `install.sh` file is the entry point.  Run it with the `-h` option to see its full help text.  Since it performs operations such as starting containers and overwriting partitions, it must be run as root.

The command should usually be given at least one argument: a shell file defining settings for the installation.  There are a few of these files under the `examples` directory for reference.  Their definitions override those from the distro or global level, but there are seven optional definitions that are system-specific.

  - `options`: an associative array of major settings (e.g. distro, architecture, image format)
  - `slots`: an array of partition UUIDs on the target disk that are reserved for root file systems
  - `packages_buildroot`: an array of package names to install into the build container
  - `packages`: an array of package names to install into the final image
  - `initialize_buildroot`: a function that will run on the build system after the container is extracted to `$buildroot` but before any package management commands are run (which is useful to configure repositories or to copy files from the host into the container)
  - `customize_buildroot`: a function that will run in the container after `packages_buildroot` is installed and the empty target image is mounted at `/wd/root` but before `packages` is installed (which is useful to create an initial image layout or to reconfigure tools for the target installation)
  - `customize`: a function that will run in the container after `packages` is installed into `/wd/root` (which is useful for any customization of the final root file system, such as to add local users or to modify default configuration files)

The resulting installation artifacts are written to a unique output directory in the current path.  For example, `vmlinuz` (or `vmlinux` on some platforms) is the kernel and `final.img` is the root file system image (containing verity hashes if enabled) that should be written directly to a partition.  If the `uefi` option was enabled, `BOOTX64.EFI` is the UEFI executable (signed for Secure Boot by default).  If the `gpt` option was enabled, `gpt.img` is a full disk image (which is optionally executable if a command was written to `launch.sh`).

For a quick demonstration, it can technically be run with no options.  In this case, it will produce a Fedora image containing `bash` that can be run in a container.

    bash -x install.sh
    systemd-nspawn -i output.*/final.img

For a bootable system example with no configuration file, use `-S` to compress the root file system, `-K` to bundle it in the initrd, `-Z` to protect it with SELinux, and `-E` to save it to your EFI system partition.  If optional PEM certificate and key files were given, the executable will be signed with them.  It can then be booted with the UEFI shell or by running `chainloader` in GRUB.

    bash -x install.sh -KSZE /boot/efi/EFI/BOOT/DEMO.EFI -c cert.pem -k key.pem

Some other options are available to modify image settings for testing, such as `-d` to pick a distro, `-p` to add packages, and `-a` to add a user account with no password for access to the system.

    bash -x install.sh -KV -d ubuntu -p 'kbd man-db nano sudo' -a admin::sudo

## License

The majority of the code in this repository is just writing configuration files, which I do not believe to be covered by copyright.  Any nontrivial components of this repository should be considered to be under the GNU GPL version 3 or later.  The license text is in the `COPYING` file.

## Feature Support

Six distros are supported: *Arch*, *CentOS* (9), *Fedora* (34 and the default 35), *Gentoo*, *openSUSE* (Tumbleweed), and *Ubuntu* (21.04 and the default 21.10).  This installer only implements features as supported in the distros themselves; i.e. it does not build newer package versions or take better tools from other distros to accomplish tasks.  As such, a different feature set is available depending on the distro choice.  The following describes the level of support for some of the major features across distros.

| Status         | Definition                            |
| :---:          | :---                                  |
| :star:         | fully supported                       |
| :warning:      | fully supported with hacks            |
| :construction: | partially supported                   |
| :fire:         | unsupported but feasible to implement |
| :skull:        | hopelessly unsupported                |

**Cross-building**:  A target architecture can be specified to build an image for a processor different than the build system.

  * :star: *Gentoo* supports cross-compiling to any architecture for any image type.
  * :construction: *openSUSE*, and *Ubuntu* support building i686 containers on x86_64 systems.
  * :skull: *Arch*, *CentOS*, and *Fedora* can only create images for the same architecture as the build system.

**Bootable**:  The bootable option produces a kernel and other boot-related files in addition to the root file system.  This option should always be used unless a container is being built.

  * :star: *Arch*, *CentOS*, *Fedora*, *openSUSE*, and *Ubuntu* support the bootable option by using the distro kernel (preferring a security-hardened variant where available) and including early microcode updates for all supported CPU types.  This should make the images portable across all hardware supported by the distro and architecture.
  * :warning: *Gentoo* can use a default distro kernel on a handful of common architectures, but it is configured so that it doesn't build or require an initrd.  Early microcode updates need to be handled separately.  Alternatively, configuration files can be provided to build a custom kernel instead, which can support any architecture and bundle microcode/firmware files for the target system.

**RAM Disk**:  The root file system image can be included in an initrd for a bootable system so that it does not need to be written to a partition.  This option runs the system entirely in RAM.  When not using SquashFS, verity, or SELinux, no file system image is produced; the entire root directory is packed directly into the initrd.

  * :star: *Arch*, *CentOS*, *Fedora*, *Gentoo*, *openSUSE*, and *Ubuntu* support running in RAM.

**UEFI / Secure Boot**:  UEFI support entails building a unified executable that contains the kernel, its command-line, and optional components like an initrd and boot logo.  This is intended to include everything needed to boot into the root file system in a single file.  These UEFI binaries are signed for Secure Boot by default.  The certificate and private key can be provided, or temporary keys will be generated for each build instead.

  * :star: *Arch*, *CentOS*, *Fedora*, *Gentoo*, *openSUSE*, and *Ubuntu* support building UEFI binaries with Secure Boot signatures.

**SELinux**:  The SELinux option will install the distro's targeted policy, label the file system accordingly, and enable SELinux enforcement on boot.

  * :star: *CentOS* and *Fedora* support SELinux in enforcing mode.
  * :construction: *Gentoo*, *openSUSE*, and *Ubuntu* support SELinux, but their policies are experimental and have issues, so they only run in permissive mode by default.
  * :fire: *Arch* does not support SELinux without major customization via AUR, which is not integrated into the build.

**Read-only Root**:  When building an immutable image in general, a read-only file system is used for the installation.

  * :star: *Arch*, *Fedora*, *Gentoo*, *openSUSE*, and *Ubuntu* create a packed uncompressed EROFS image for the root file system.
  * :construction: *CentOS* disables EROFS support, so it uses ext4 with the read-only flag set.

**SquashFS**:  Immutable systems can opt to use SquashFS for a compressed root file system to save space at the cost of runtime decompression.  All compression in the installer (kernels, initrds, root images, binary packages, etc.) aims to standardize on zstd for the best size-to-resource-utilization ratio.

  * :star: *Arch*, *CentOS*, *Fedora*, *Gentoo*, *openSUSE*, and *Ubuntu* support SquashFS with zstd compression.

**Verity**:  Verity is cryptographic integrity verification that guarantees a file system has not been modified.  It creates a read-only device mapper node that returns I/O errors if anything has changed.  The verity hash block created for the root file system is directly appended to the image so there is only one file to manage for updates.  The root hash is stored in the kernel command-line, so a UEFI Secure Boot signature authenticates the entire file system.

  * :star: *Arch*, *CentOS*, *Fedora*, *Gentoo*, *openSUSE*, and *Ubuntu* support verity.
  * :warning: *Arch*, *CentOS*, and *openSUSE* have a userspace hack until they enable `CONFIG_DM_INIT`.

**Verity Signatures**:  The verity root hash can be signed and loaded into a kernel keyring.  This has no security benefits for the root file system over verity with Secure Boot, but it can be used to trust additional file systems built at a later date.  It also works on platforms that do not support UEFI, making the kernel the root of trust for the file system instead of the firmware in those cases.  This option enables a setting that requires all verity devices to include a valid signature.

  * :star: *Gentoo* supports verity signatures by creating an initrd to handle the userspace component.
  * :construction: *Fedora* and *Ubuntu* support verity signatures on non-UEFI systems.  The certificate is written into the uncompressed kernel `vmlinux`, which strips off the Linux UEFI stub and makes the kernel unbootable on UEFI.
  * :fire: *Arch* and *CentOS* cannot use verity signatures until they enable `CONFIG_SYSTEM_EXTRA_CERTIFICATE`.
  * :fire: *openSUSE* cannot use verity signatures until they enable `CONFIG_DM_VERITY_VERIFY_ROOTHASH_SIG`.

**IPE**:  Integrity Policy Enforcement is an experimental (still not upstream) Linux security module that restricts file usage based on integrity properties.  It is currently used to limit sources of kernel resources like firmware and modules, and it can also block programs from executing.  IPE currently requires pairing with the RAM disk or verity option to be usable.  When using an initrd/initramfs, the default policy trusts the initial root file system, so the initrd should be verified (e.g. with Secure Boot).  Without verity signatures, the default policy trusts only the specific hash of the root file system.  With verity signatures, it trusts any verity device with a valid signature, so the system is extensible.

  * :construction: *Gentoo* supports IPE, but the patch seems to cause problems with booting stable kernels.  It is only for experimentation at this point.
  * :fire: *Arch*, *CentOS*, *Fedora*, *openSUSE*, and *Ubuntu* do not rebuild kernels to patch in IPE support.

## To Do

**Support configuring systemd with the etc Git overlay.**  The `/etc` directory contains the read-only default configuration files with a writable overlay, and if Git is installed, the modified files in the overlay are tracked in a repository.  The repository database is saved in `/var` so the changes can be stored persistently.  At the moment, the Git overlay is mounted by a systemd unit in the root file system, which happens too late to configure systemd behavior.  It needs to be set up by an initrd before pivoting to the real root file system.

**Prepopulate a Wine prefix for the game containers.**  I need to figure out what Wine needs so it can initialize itself in a chroot instead of a full container.  The games currently generate the Wine prefix (and its `C:` drive) every run as a workaround.  By installing a prebuilt `C:` drive and Wine prefix with the GOG registry changes applied, runtime memory will be reduced by potentially hundreds of megabytes and startup times will improve by several seconds.

**Provide server examples.**  The only bootable system examples right now are simple standalone workstations.  I should try to generalize some of my server configurations, or set up a network workstation example with LDAP/Kerberos/NFS integration.  Also, something should demonstrate persistent encrypted storage, which servers are going to require.  (Just add one line to `/etc/crypttab` and `/etc/fstab` to mount `/var`.)

**Automate generating a QEMU pflash image for Secure Boot variables with the given certificate.**  This would be useful for generating a VM image that can actually verify Secure Boot signatures when it is enabled.  It would also get the certificate into the platform keyring via `db` so other things can use it in the binary distros.
