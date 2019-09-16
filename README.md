# GNU/Linux Distro Installer

This is a collection of shell functions to build secure Linux-based operating system images.  They are highly specific to my setup and probably won't be useful to anyone else.  I am writing this project in an attempt to automate and unify a lot of the things I would do manually when installing systems.  In case anyone finds this: there are many other projects with similar goals that might better suit your needs, such as `mkosi`.

## About

The primary goal here is swappable immutable disk images that are verified by verity, which is itself verified by the kernel's Secure Boot signature.  Parts of the file system such as `/home` and `/var` are mounted as tmpfs to support regular usage, but their mount units can be overridden to use persistent storage or a network file system.  This build system outputs components of a bootable system (such as the root file system image, kernel, initrd, etc.) that can be assembled as desired, but my testing focuses on three main use cases:

 1. A system's primary hard drive is GPT-partitioned with an ESP, several (maybe three to five) partitions of five or ten gigabytes reserved to store root file system images, and the rest of the disk used as an encrypted `/var` partition for persistent storage.  When this installer produces an OS image, it can also produce a UEFI executable containing the kernel, initrd, and arguments specifying the root partition's UUID and root verity hash.  A UEFI executable corresponding to each active root file system partition is written to the ESP (potentially after Secure Boot signing) so that each image can be booted interchangeably with zero configuration.  This allows easily installing updated images or migrating to different software.

 2. The installer produces a single UEFI executable that also has the entire root file system image bundled into it.  This method will not use persistent storage by default, so it can be booted on any machine from a USB key, via PXE, or just from a regular hard drive's ESP as a rescue system.

 3. All boot-related functionality is omitted, so a file system image is produced that can be used as an immutable container.  There is an option to build a launcher script into the disk image so that it is executable like a statically linked program.

## Usage

The `install.sh` file is the entry point.  Run it with `bash install.sh -h` to see its full help text.

It should be given at least one argument: a shell file defining settings for the installation.  There are a few such example files under the `examples` directory.  The resulting installation artifacts are written to a unique output directory in the current path.  For example, `vmlinuz` is the kernel, `initrd.img` is the initrd, and `final.img` is the root file system image (containing verity signatures if enabled) that should be written directly to a partition.  If the `uefi` option was enabled, `BOOTX64.EFI` is the UEFI executable that should be signed for Secure Boot.  If the `nspawn` option was enabled, `nspawn.img` is a disk image that can be executed as a program to launch the container with `systemd-nspawn`.

When `install.sh` runs, it reads `base.sh` which is a library of distro-agnostic shell functions that configure a GNU/Linux system.  It then reads one of the distro-specific library files (`centos.sh`, `gentoo.sh`, or the default `fedora.sh`) as selected in the specified settings file, which can override functions from `base.sh` if needed.  Finally, it reads and applies definitions from the specified system settings file, which can override or augment anything previously defined.  A series of these functions is then executed based on the given options to generate the installation artifacts.

For a quick demonstration, it can technically be run with no options since Fedora is the default distro.  In this case, it will produce an image containing `bash` that can be run in a container.  For example, run the installer with `-S` to produce a compressed image that can be used with the following commands as root.

    bash -x install.sh -S
    cd output.*
    systemd-nspawn --image=final.img

For a bootable system example with no configuration file, use `-S` to compress the root file system, `-K` to bundle it in the initrd, `-Z` to protect it with SELinux, and `-E` to save it to your EFI system partition.  It can then be booted with the UEFI shell or by running `chainloader` in GRUB.

    bash -x install.sh -KSZE /boot/efi/EFI/BOOT/DEMO.EFI

## License

The majority of the code in this repository is just writing configuration files, which I do not believe to be covered by copyright.  Any nontrivial components of this repository should be considered to be under the GNU GPL version 3 or later.  The license text is in the `COPYING` file.

## Status / Notes / To Do

The project is currently at the stage where I've just dumped some useful things into shell functions that are randomly scattered around the directory.  It will be completely revised at some point.  Don't expect anything in here to be stable.  Don't use this in general.

Three distros are supported to varying degrees at the moment: Fedora, CentOS, and Gentoo.  For the best support currently, build Fedora 30 images while running on a Fedora 30 host system.

### General

**Improve the command-line interface.**  Automatic Secure Boot signing should be offered as an option here, which would need to specify which key to use.  There should also be an option to take a public keyring file that is used to verify the signature of the etc Git overlay commit on checkout, and maybe an SSH key to support securely cloning the repo as a means of automated provisioning.  Maybe add an option to lock the root account and create an unprivileged user, so I don't need to hard-code an account in the example files.  Add validation error messages.

**Implement content whitelisting.**  The images currently include all installed files with an option to blacklist paths using an exclude list.  The opposite should be supported for minimal systems, where individual files, directories, entire packages, and ELF binaries (as a shortcut for all linked libraries) can be listed for inclusion and everything else is dropped.

**Maybe support reusing a build root.**  Everything is being built from scratch every time the installer runs.  For faster testing, maybe add an option to run in an existing build root and start the installation process at a specified point.

**Fix the relabel function for inactive SELinux policies.**  I need to look into whether anything supports labeling a file system with labels that aren't from the host system's active policy.  Assuming not, I'll just always install into an ext4 image first and generate an initrd containing the target policy and `policycoreutils`, then replace the `relabel` function with a `qemu -kernel vmlinuz -initrd relabel.img ext4.img` call.

**Support an etc Git overlay for real.**  The `/etc` directory contains the read-only default configuration files with a writable overlay, and if Git is installed, the modified files in the overlay are tracked in a repository.  The repository database is saved in `/var` so the changes can be stored persistently.  At the moment, the Git overlay is mounted by a systemd generator when it's already running in the root file system.  This allows configuring services, but not things like `fstab` or other generators.  It needs to be set up by an initrd before pivoting to the real root file system (also so an encrypted `/var` can be mounted), and it should verify the commit's signature so that everything is cryptographically verified in the booted system.

**Maybe add a disk formatter or build a GRUB image.**  I have yet to decide if the pieces beneath the distro images should be outside the scope of this project, since they might not be worth automating.  There are two parts to consider.  First, whether to format a disk with an ESP, root partition slots, and an encrypted `/var` partition.  Second, whether to configure, build, and sign a GRUB UEFI executable to be written to an ESP as the default entry.  I also have two use cases to handle with GRUB.  In the case of a formatted disk with root partitions, it needs to have a menu allowing booting into any of the installed root partitions, but it should default to the most recently updated partition unless overridden.  In the case where I'd fill a USB drive with just an ESP and populate it with images containing bundled root file systems, GRUB needs to detect which machine booted it via SMBIOS and automatically chainload an appropriate OS for that system.

**Fix the UEFI splash image colors.**  The distro logo colors are off when booting a UEFI executable, even though they are correct when viewing the source image.  Figure out how the colors need to be mapped.

### Fedora

**Support different Fedora releases.**  The Fedora container is signed with a different key for each release, so in order to use anything other than the latest version, a keyring for supported releases needs to be maintained.

**Report when the image should be updated.**  When a system saves the RPM database and has network access, it should automatically check Fedora updates for enhancements, bug fixes, and security issues so it can create a report advising when an updated immutable image should be created and applied.  I will probably implement this in a custom package in my local repo and integrate it with a real monitoring server, but I am noting it here in case I decide to add it to the base system and put a report in root's MOTD (to provide the information without assumptions about network monitoring).  The equivalent can be done for CentOS or via GLSAs, but Fedora is my priority here.

**Move the ramdisk option to dracut.**  I used to build a custom minimal `busybox` initrd that included only the Fedora kernel modules needed for a machine, so it could either download a root file system image with no kernel installation into its tmpfs or copy it off the USB boot disk.  The `ramdisk` option is currently using a stripped version of that idea, but it's going to be a bigger maintenance burden than just using dracut.  The squashfs compression is so good that bundling the entire image (with a full kernel installation) into the initrd is still well under the FAT32 ESP file size limit.  Maybe I can revisit ideas for the minimal version later.

### CentOS

**Drop CentOS 7 support as soon as a CentOS 8 image is available.**  As usual, the software included with CentOS is wildly obsolete.  CentOS 7 doesn't even include networkd or a UEFI stub to create bootable files.  Some of its shortcomings can be addressed by stealing files from a Fedora package, but part of the reason for using the target distro as the build root is so that any distro-specific changes are reflected in the final output.  Supporting features by using another distro is counter to this goal, so it is better to just not support versions that don't implement required functionality.

**Fix failing units.**  The `hostnamed` service is failing with a resource error.  Look into that so systems boot cleanly.

### Gentoo

**Support real cross-compiling.**  I'm eventually going to use this to produce images for slow embedded chips from an amd64 workstation, so `crossdev` needs to be configured properly.

**Add some examples.**  All the example systems are currently Fedora-based, but Gentoo is definitely the most flexible option and needs a few practical examples so it is clear what it can do.

### Example Systems

**Prepopulate a Wine prefix for the game containers.**  I need to figure out what Wine needs so it can initialize itself in a chroot instead of a full container.  The games currently generate the Wine prefix (and its `C:` drive) every run as a workaround.  By installing a prebuilt `C:` drive and Wine prefix with the GOG registry changes applied, runtime memory will be reduced by potentially hundreds of megabytes and startup times will improve by several seconds.

**Provide servers.**  The only bootable system example right now is a standalone desktop workstation.  I should try to generalize some of my server configurations, or set up a network workstation example with LDAP/Kerberos/NFS integration.  Maybe I'll just add some of my servers as is, but that seems unhelpful since they're specific to my network setup.
