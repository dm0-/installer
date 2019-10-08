# GNU/Linux Distro Installer

This is a collection of shell functions to build secure Linux-based operating system images.  They are highly specific to my setup and probably won't be useful to anyone else.  I am writing this project in an attempt to automate and unify a lot of the things I would do manually when installing systems.  In case anyone finds this: there are many other projects with similar goals that might better suit your needs, such as `mkosi`.

## About

The primary goal here is swappable immutable disk images that are verified by verity, which is itself verified by the kernel's Secure Boot signature.  Parts of the file system such as `/home` and `/var` are mounted as tmpfs to support regular usage, but their mount units can be overridden to use persistent storage or a network file system.  This build system outputs components of a bootable system (such as the root file system image, kernel, initrd, etc.) that can be assembled as desired, but my testing focuses on three main use cases:

 1. A system's primary hard drive is GPT-partitioned with an ESP, several (maybe three to five) partitions of five or ten gigabytes reserved to store root file system images, and the rest of the disk used as an encrypted `/var` partition for persistent storage.  When this installer produces an OS image, it can also produce a UEFI executable containing the kernel, initrd, and arguments specifying the root partition's UUID and root verity hash.  A UEFI executable corresponding to each active root file system partition is written to the ESP (potentially after Secure Boot signing) so that each image can be booted interchangeably with zero configuration.  This allows easily installing updated images or migrating to different software.

    Example installation: `bash -x install.sh -VZE /boot/EFI/BOOT/BOOTX64.EFI -IP e08ede5f-56d4-4d6d-b8d9-abf7ef5be608 workstation.sh`

 2. The installer produces a single UEFI executable that also has the entire root file system image bundled into it.  This method will not use persistent storage by default, so it can be booted on any machine from a USB key, via PXE, or just from a regular hard drive's ESP as a rescue system.

    Example installation: `bash -x install.sh -KSE /boot/EFI/BOOT/RESCUE.EFI -a admin::wheel -p 'cryptsetup dosfstools e2fsprogs kbd kernel-modules-extra lvm2 man-db man-pages sudo vim-minimal'`

 3. All boot-related functionality is omitted, so a file system image is produced that can be used as a container.  There is an option to build a launcher script into the disk image so that it is executable like a statically linked program.

    Example installation: `bash -x install.sh -S app.sh`

## Usage

The `install.sh` file is the entry point.  Run it with `bash install.sh -h` to see its full help text.  Since it performs operations such as starting containers and overwriting partitions, it must be run as root.

It should be given at least one argument: a shell file defining settings for the installation.  There are a few such example files under the `examples` directory.  The resulting installation artifacts are written to a unique output directory in the current path.  For example, `vmlinuz` is the kernel, `initrd.img` is the initrd, and `final.img` is the root file system image (containing verity signatures if enabled) that should be written directly to a partition.  If the `uefi` option was enabled, `BOOTX64.EFI` is the UEFI executable that should be signed for Secure Boot.  If the `nspawn` option was enabled, `nspawn.img` is a disk image that can be executed as a program to launch the container with `systemd-nspawn`.

For a quick demonstration, it can technically be run with no options.  In this case, it will produce a Fedora image containing `bash` that can be run in a container.

    bash -x install.sh
    cd output.*
    systemd-nspawn --image=final.img

For a bootable system example with no configuration file, use `-S` to compress the root file system, `-K` to bundle it in the initrd, `-Z` to protect it with SELinux, and `-E` to save it to your EFI system partition.  It can then be booted with the UEFI shell or by running `chainloader` in GRUB.

    bash -x install.sh -KSZE /boot/efi/EFI/BOOT/DEMO.EFI

Some other options are available to modify image settings for testing, such as `-d` to pick a distro, `-p` to add packages, and `-a` to add a user account with no password for access to the system.

    bash -x install.sh -KSVZ -d centos -p 'kbd man-db passwd sudo vim-minimal' -a user::wheel

## License

The majority of the code in this repository is just writing configuration files, which I do not believe to be covered by copyright.  Any nontrivial components of this repository should be considered to be under the GNU GPL version 3 or later.  The license text is in the `COPYING` file.

## Status / Notes / To Do

The project is currently at the stage where I've just dumped some useful things into shell functions that are randomly scattered around the directory.  It will be completely revised at some point.  Don't expect anything in here to be stable.  Don't use this in general.

A few bits currently expect to be running on x86_64.  Three distros are supported to varying degrees:

  - Fedora supports all features, but only Fedora 30 can be used since it is the only release with an imported GPG key.
  - CentOS does not include networkd, so you should always install `NetworkManager` for networking (and `iptables-services` for a firewall).  CentOS 7 is too old to support building a UEFI image.
  - Gentoo supports all features in theory, but needs to be reworked to support nontrivial builds.  Its SELinux policy is currently unsupported with systemd, so it should not be run in enforcing mode.

### General

**Improve the command-line interface.**  Automatic Secure Boot signing should be offered as an option here, which would need to specify which key to use.  There should also be an option to take a public keyring file that is used to verify the signature of the etc Git overlay commit on checkout, and maybe an SSH key to support securely cloning the repo as a means of automated provisioning.  Add validation error messages.

**Implement content whitelisting.**  (There is a prototype in *TheBindingOfIsaac.sh*.)  The images currently include all installed files with an option to blacklist paths using an exclude list.  The opposite should be supported for minimal systems, where individual files, directories, entire packages, and ELF binaries (as a shortcut for all linked libraries) can be listed for inclusion and everything else is dropped.

**Support an etc Git overlay for real.**  The `/etc` directory contains the read-only default configuration files with a writable overlay, and if Git is installed, the modified files in the overlay are tracked in a repository.  The repository database is saved in `/var` so the changes can be stored persistently.  At the moment, the Git overlay is mounted by a systemd generator when it's already running in the root file system.  This allows configuring services, but not things like `fstab` or other generators.  It needs to be set up by an initrd before pivoting to the real root file system, and it should verify the commit's signature so that everything is cryptographically verified in the booted system.

**Maybe add a disk formatter or build a GRUB image.**  I have yet to decide if the pieces beneath the distro images should be outside the scope of this project, since they might not be worth automating.  There are two parts to consider.  First, whether to format a disk with an ESP, root partition slots, and an encrypted `/var` partition.  Second, whether to configure, build, and sign a GRUB UEFI executable to be written to an ESP as the default entry.  I also have two use cases to handle with GRUB.  In the case of a formatted disk with root partitions, it needs to have a menu allowing booting into any of the installed root partitions, but it should default to the most recently updated partition unless overridden.  In the case where I'd fill a USB drive with just an ESP and populate it with images containing bundled root file systems, GRUB needs to detect which machine booted it via SMBIOS and automatically chainload an appropriate OS for that system.

**Fix the UEFI splash image colors.**  The distro logo colors are off when booting a UEFI executable, even though they are correct when viewing the source image.  Figure out how the colors need to be mapped.

**Fix squashfs SELinux labels.**  (There is a prototype in CentOS.)  The squashfs image appears to use the default context for a label that wasn't defined in the host policy (at least with CentOS 7).  This can result in errors in some cases.  If there is no easy way to fix this, the dumb solution of using the labeling VM to run `mksquashfs` works, but it will be horribly slow without passing through a host KVM device.  (The uncompressed ext4 image is not affected.)

**Instrument returning an error state from the SELinux labeling virtual machine.**  If labeling fails right now, the build system won't know about it.

**Use the list of excluded paths in ext4.**  Only squashfs is dropping the files.

**Extend the package finalization function to cover all of the awful desktop caches.**  Right now, it's only handling glib schemas to make GNOME tolerable, but every other GTK library and XDG specification has its own cache database that technically needs to be regenerated to cover any last system modifications.  To make this thoroughly unbearable, none of these caching applications supports a target root directory, so they all will need to be installed in the final image to update the databases.  I will most likely end up having a dropin directory for package finalization files when this gets even uglier.

### Fedora

**Support different Fedora releases.**  The Fedora container is signed with a different key for each release, so in order to use anything other than the latest version, a keyring for supported releases needs to be maintained.  A workaround is to set e.g. `options[release]=31` in `customize_buildroot` to install packages from that release into the image after the buildroot has been created with a supported release.

**Report when the image should be updated.**  When a system saves the RPM database and has network access, it should automatically check Fedora updates for enhancements, bug fixes, and security issues so it can create a report advising when an updated immutable image should be created and applied.  I will probably implement this in a custom package in my local repo and integrate it with a real monitoring server, but I am noting it here in case I decide to add it to the base system and put a report in root's MOTD (to provide the information without assumptions about network monitoring).  The equivalent can be done for CentOS or via GLSAs, but Fedora is my priority here.

### CentOS

There is nothing planned to change here at this point.  CentOS must be perfect.  All known shortcomings in the generated images are due to the status of the distro (e.g. lack of networkd, lack of a UEFI stub in 7, etc.), so they will not be fixed by this script.

### Gentoo

**Support real cross-compiling.**  I'm eventually going to use this to produce images for slow embedded chips from an amd64 workstation, so `crossdev` needs to be configured properly.

**Figure out if the Gentoo SELinux policy is feasible to enforce with systemd.**  It's still unsupported by the distro and causes severe problems with both `strict` and `targeted`.

**Add some examples.**  All the example systems are currently Fedora-based, but Gentoo is definitely the most flexible option and needs a few practical examples so it is clear what it can do.

### Example Systems

**Prepopulate a Wine prefix for the game containers.**  I need to figure out what Wine needs so it can initialize itself in a chroot instead of a full container.  The games currently generate the Wine prefix (and its `C:` drive) every run as a workaround.  By installing a prebuilt `C:` drive and Wine prefix with the GOG registry changes applied, runtime memory will be reduced by potentially hundreds of megabytes and startup times will improve by several seconds.

**Provide servers.**  The only bootable system example right now is a standalone desktop workstation.  I should try to generalize some of my server configurations, or set up a network workstation example with LDAP/Kerberos/NFS integration.  Maybe I'll just add some of my servers as is, but that seems unhelpful since they're specific to my network setup.
