# AutoHCK image creation

AutoHCK is a tool for automating HCK/HLK testing, doing all the boilerplate steps in the process leaving you with simply choosing which driver you want to test on what OS.

## Manual installation

Detailed instructions available at [HLK-Setup-Scripts](https://github.com/HCK-CI/HLK-Setup-Scripts).
Images should be copied to the images directory as configured in the `config.json` file.

## Automatic installation preparation

### Windows ISO preparation

1. Create a directory for all ISO image storing.
2. Write this path into the `config.json` file (see AutoHCK configuration section).
3. Download ISO which is needed for a specific platform installation and copy it into the created directory.
4. Add information about this iso into `lib/engines/hckinstall/iso.json` (see AutoHCK configuration section).

### Windows ISO preparation for installation in UEFI mode

In case when UEFI firmware, not BIOS is booted, the Windows installer always asks to press any key to boot from CD/DVD. AutoHCK can't do this in the proper way. 

So you should patch ISO and replace UEFI boot loader code. By default, ISO uses the EFI boot code from efisys.bin. There is also an efisys_noprompt.bin boot code that skips the prompt step.

Please use the following commands to create a new ISO:

using mkisofs:
```
mount original.iso /mnt
mkisofs \
    -iso-level 4 \
    -l \
    -R \
    -udf \
    -D \
    -b "boot/etfsboot.com" \
    -no-emul-boot \
    -boot-load-size 8 \
    -hide boot.catalog \
    -eltorito-alt-boot \
    -allow-limited-size \
    -no-emul-boot \
    -e "efi/boot/bootx64.efi" \
    -b "efi/microsoft/boot/efisys_noprompt.bin" \
    -o new.iso \
    /mnt
```

using xorriso:
```
mount original.iso /mnt
xorriso -as mkisofs \
    -iso-level 4 \
    -J -l -D -N \
    -joliet-long \
    -relaxed-filenames \
    -V "WINDOWS" \
    -b "boot/etfsboot.com" \
    -no-emul-boot \
    -boot-load-size 8 \
    -hide boot.catalog \
    -eltorito-alt-boot \
    -no-emul-boot \
    -e "efi/boot/bootx64.efi" \
    -b "efi/microsoft/boot/efisys_noprompt.bin" \
    -o new.iso \
    /mnt

umount /mnt
```

### AutoHCK configuration

Configure AutoHCK to have all information for building VM images. Edit the next files according to templates present in each file.

1. `lib/engines/hckinstall/iso.json` - contains information about Windows ISO for each HCK/HLK platform. The following fields should be configured:
   - **platform_name** - The platform name should be the same as in the `platforms.json` file.
   - **path** - contains the path relative to `iso_path` option in the config file to the corresponding ISO image.
   - **windows_image_names** - contains image name from `install.wim` file in ISO. To get a list of available images use the next commands:
      * `dism /get-wiminfo /wimfile:D:\sources\install.wim` on Windows.
      * `wiminfo /mnt/sources/install.wim` on Linux (wimlib is required).
   - **product_key** - contains a valid key for the corresponding Windows image. Generic keys from MSDN can be used [KMS Client Activation Keys](https://learn.microsoft.com/en-us/windows-server/get-started/kms-client-activation-keys).

2. `lib/engines/hckinstall/hckinstall.json` - contains the specific configuration for the install engine. The following fields should be configured:
   - **hck_setup_scripts_path** - path to HLK-Setup-Scripts repository.
   - **answer_files** (_advanced_) -  list of the unattended answer file for automatic Windows installation. These files are part of the HLK-Setup-Scripts repository.
   - **studio_install_timeout** (_advanced_) - timeout before the installation of the Studio VM is considered a failure.
   - **client_install_timeout** (_advanced_) - timeout before the installation of the Client VMs is considered a failure.

3. `config.json` - contains the general AutoHCK configuration. The following fields should be configured:
   - **iso_path** - absolute path to the directory where ISO stored.

4. `lib/engines/hckinstall/kit.json` - contains information about each HCK/HLK kit. The following fields should be configured:
   - **kit** - The kit name should be the same as in the `platforms.json` file.
   - **download_url** - contains the URL for download the kit online installer.

5. `lib/engines/hckinstall/studio_platform.json` - contains information on which platform should be used for each HCK/HLK kit. The following fields should be configured:
   - **kit** - The kit name should be the same as in the `platforms.json` file.
   - **platform_name** - The platform name for Studio VM should be the same as in the `platforms.json` file.

6. `lib/setupmanagers/<setup_manager>/<setup_manager>.json` - contains information for specific setup manager. Please edit the setup manager which you need. Existing setup managers config:
   - `lib/setupmanagers/physhck/physhck.json`
   - `lib/setupmanagers/qemuhck/qemu_machine.json`

Notes:
   - Please do **not** edit any advanced configurations if you don't understand what it does!
   - All config files with generic config are present in the repository, you can use them as templates.

### Extra software installation

The `extra_software` option can be specified in the following files:
  - `drivers.json` - will be used in test mode only
  - `lib/engines/hckinstall/kit.json` - will be used in install mode only
  - `lib/engines/hcktest/<paltform>.json` - will be used in install and test modes

According to the file, the software will be installed during image creating (install mode) or during driver testing (test mode)

## Automatic installation

To run installation use the `install` AutoHCK command-line command. AutoHCK will create 3 images (studio and 2 clients) and perform the installation.

In case when studio image exists, it will be reused. To recreate studio image use `--force` option

### Examples
```
bin/ns bin/auto_hck install -p Win10_2004x86
bin/ns bin/auto_hck install -p Win2019x64 --force
```

## Related information

Automatic installation is performed by using answer files. This is Windows's ability to install and configure the system from the scratch. See the MDSN article for more details:

   - [Automating Windows setup](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup)
   - [Automate Windows configuration](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/update-windows-settings-and-scripts-create-your-own-answer-file-sxs)
