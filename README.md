# GNU/Linux Distro Installer

This is a collection of shell functions to build secure Linux-based operating system images.  I am writing this project in an attempt to automate and unify a lot of the things I would do manually when installing systems, as well as to cross-compile images from fast modern hardware tuned for old embedded chips and uncommon CPU architectures.

## About

The primary goal here is interchangeable immutable disk images that are verified by verity, which is itself verified by the kernel's Secure Boot signature on UEFI platforms.  This script creates a container to run the build procedure which outputs components of an installed operating system (such as the root file system image, kernel, initrd, etc.) that can be assembled as desired, but my testing focuses on three main use cases:

 1. A system's bootable hard drive is GPT-partitioned with an ESP, several (maybe three to five) partitions of five or ten gigabytes reserved to store root file system images, and the rest of the disk used as an encrypted `/var` partition for persistent storage.  A signed UEFI executable corresponding to each active root file system partition is written to the ESP so that each image can be booted interchangeably with zero configuration.  This allows easily installing updated images or migrating to different software.

    Example installation: `bash -x install.sh -E /boot/EFI/BOOT/BOOTX64.EFI -IP e08ede5f-56d4-4d6d-b8d9-abf7ef5be608 examples/systems/desktop-fedora.sh`

 2. The installer produces a single UEFI executable that has the entire root file system image bundled into it.  Such a file can be booted on any machine from a USB key, via PXE, or just from a regular hard drive's ESP as a rescue system.

    Example installation: `bash -x install.sh -KSE /boot/EFI/BOOT/RESCUE.EFI -a admin::wheel -p 'cryptsetup dosfstools e2fsprogs kbd kernel-modules-extra lvm2 man-db man-pages sudo vim-minimal'`

 3. All boot-related functionality is omitted, so a file system image is created that can be used as a container.

    Example installation: `bash -x install.sh examples/containers/VVVVVV.sh`

The installer can produce an executable disk image for testing each of these configurations if a command to launch a container or virtual machine is specified.

## Usage

The `install.sh` file is the entry point.  Run it with `bash install.sh -h` to see its full help text.  Since it performs operations such as starting containers and overwriting partitions, it must be run as root.

The command should usually be given at least one argument: a shell file defining settings for the installation.  There are a few such example files under the `examples` directory.  The file should at least append to the associative array named `options` to define required settings that will override command-line options.  It should append to the `packages` array as well to specify what gets installed into the image.  The installed image can be modified by defining a function `customize` which will run in the build container with the image mounted at `/wd/root`.  For more complex modifications, append to the array `packages_buildroot` to install additional packages into the container, and define a function `customize_buildroot` which runs on the host system after creating the container at `$buildroot`.

The resulting installation artifacts are written to a unique output directory in the current path.  For example, `vmlinuz` (or `vmlinux` on some platforms) is the kernel and `final.img` is the root file system image (containing verity signatures if enabled) that should be written directly to a partition.  If the `uefi` option was enabled, `BOOTX64.EFI` is the UEFI executable (signed for Secure Boot if a certificate and key were given).  If the `executable` option was enabled, `disk.exe` is a disk image that can also be executed as a program.

For a quick demonstration, it can technically be run with no options.  In this case, it will produce a Fedora image containing `bash` that can be run in a container.

    bash -x install.sh
    systemd-nspawn -i output.*/final.img

For a bootable system example with no configuration file, use `-S` to compress the root file system, `-K` to bundle it in the initrd, `-Z` to protect it with SELinux, and `-E` to save it to your EFI system partition.  If optional PEM certificate and key files were given, the executable will be signed with them.  It can then be booted with the UEFI shell or by running `chainloader` in GRUB.

    bash -x install.sh -KSZE /boot/efi/EFI/BOOT/DEMO.EFI -c cert.pem -k key.pem

Some other options are available to modify image settings for testing, such as `-d` to pick a distro, `-p` to add packages, and `-a` to add a user account with no password for access to the system.

    bash -x install.sh -KSVZ -d centos -p 'kbd man-db passwd sudo vim-minimal' -a user::wheel

## License

The majority of the code in this repository is just writing configuration files, which I do not believe to be covered by copyright.  Any nontrivial components of this repository should be considered to be under the GNU GPL version 3 or later.  The license text is in the `COPYING` file.

## Status / Notes / To Do

The project may be completely revised at some point, so don't expect anything in here to be stable.  Some operations might still require running on x86_64 for the build system.  Five distros are supported to varying degrees:

  - Fedora supports everything besides EROFS, but only Fedora 30 and 31 (the default) can be used.  Fedora 30 is the last version to support i686.
  - CentOS is too old to support EROFS.  CentOS 7 systemd is too old to support building a UEFI image and the persistent `/etc` Git overlay.
  - Gentoo supports all features in theory, but its SELinux policy is unsupported with systemd upstream, so it is only running in permissive mode.
  - Arch supports everything besides SELinux, since AUR is not yet integrated with the build.  Systems can theoretically force SELinux with custom scripts.
  - openSUSE supports all features, but its SELinux policy is experimental and broken, so it runs in permissive mode.  It is the only modern binary disto with i686 support.

### General

**Support configuring systemd with the etc Git overlay.**  The `/etc` directory contains the read-only default configuration files with a writable overlay, and if Git is installed, the modified files in the overlay are tracked in a repository.  The repository database is saved in `/var` so the changes can be stored persistently.  At the moment, the Git overlay is mounted by a systemd unit in the root file system, which happens too late to configure systemd behavior.  It needs to be set up by an initrd before pivoting to the real root file system.

**Support cross-building bootable images from binary distros.**  Gentoo can currently be used to build any image types for any architecture, but binary distros can only create bootable images with the same architecture as the build system (or containers with a compatible architecture, like i686 on x86_64).  The problem is that a bootable image needs a kernel and initrd for the target architecture.  This can be fixed with a QEMU binfmt handler and running dracut in a chroot.  Maybe the kernel/initrd files could be installed in an overlay over the target image root to reduce redundant base package installations.

**Implement content whitelisting.**  (There is a prototype in *TheBindingOfIsaac.sh*.)  The images currently include all installed files with an option to blacklist paths using an exclude list.  The opposite should be supported for minimal systems, where individual files, directories, entire packages, and ELF binaries (as a shortcut for all linked libraries) can be listed for inclusion and everything else is dropped.

**Maybe add a disk formatter or build a GRUB image.**  I have yet to decide if the pieces beneath the distro images should be outside the scope of this project, since they might not be worth automating.  There are two parts to consider.  First, whether to format a disk with an ESP, root partition slots, and an encrypted `/var` partition.  Second, whether to configure, build, and sign a GRUB UEFI executable to be written to an ESP as the default entry.  I also have two use cases to handle with GRUB.  In the case of a formatted disk with root partitions, it needs to have a menu allowing booting into any of the installed root partitions, but it should default to the most recently updated partition unless overridden.  In the case where I'd fill a USB drive with just an ESP and populate it with images containing bundled root file systems, GRUB needs to detect which machine booted it via SMBIOS and automatically chainload an appropriate OS for that system.

**Use the list of excluded paths in ext4 and EROFS.**  Only squashfs is dropping the files.  SELinux might be a problem with EROFS until this is fixed.

**Extend the package finalization function to cover all of the awful desktop caches.**  Right now, it's only handling glib schemas to make GNOME tolerable, but every other GTK library and XDG specification has its own cache database that technically needs to be regenerated to cover any last system modifications.  To make this thoroughly unbearable, none of these caching applications supports a target root directory, so they all will need to be installed in the final image to update the databases.  I will most likely end up having a dropin directory for package finalization files when this gets even uglier.

**Fix the logind/DRM race.**  It looks like systemd-logind can try to start before the DRM module is ready (at least on QEMU), which prevents GDM from starting.  Restart systemd-logind to get it working.

### Fedora

**Sit and wait until EROFS kernel support is in a release.**

### CentOS

There is nothing planned to change here at this point.  CentOS must be perfect.  All known shortcomings in the generated images are due to the status of the distro (e.g. CentOS 7 is too old to have a UEFI stub), so they will not be fixed by this script.

### Gentoo

No major changes are planned for Gentoo in this script.  Work will continue upstream to properly fix workarounds and make everything more efficient.

### Arch

**Support SELinux.**  This probably entails adding a function to enable AUR packages during the build like RPM Fusion in Fedora.  There might be some ugly manual steps since AUR has separate packages built with SELinux support that replace both optional and core packages.

### openSUSE

No changes are planned for openSUSE.  Leap releases might be supported one day for a more stable target, but it is only needed as a rolling release distro right now.

### Example Systems

**Prepopulate a Wine prefix for the game containers.**  I need to figure out what Wine needs so it can initialize itself in a chroot instead of a full container.  The games currently generate the Wine prefix (and its `C:` drive) every run as a workaround.  By installing a prebuilt `C:` drive and Wine prefix with the GOG registry changes applied, runtime memory will be reduced by potentially hundreds of megabytes and startup times will improve by several seconds.

**Provide servers.**  The only bootable system examples right now are simple standalone workstations.  I should try to generalize some of my server configurations, or set up a network workstation example with LDAP/Kerberos/NFS integration.  Also, something should demonstrate persistent encrypted storage, which servers are going to require.  (Just add one line to `/etc/crypttab` and `/etc/fstab` to mount `/var`.)
