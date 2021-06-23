# AutoHCK image creation

AutoHCK is a tool for automating HCK/HLK testing, doing all the boilerplate steps in the process leaving you with simply choosing which driver you want to test on what OS.

## Manual installation

Detailed instructions available at [HLK-Setup-Scripts](https://github.com/HCK-CI/HLK-Setup-Scripts).
Images should be copied to the images directory as configured in the `config.json` file.

## Automatic installation preparation

### Windows ISO preparation

1. Create a directory for all ISO image storing.
2. Write this path into the `config.json` file (see AutoHCK configuration section).
3. Download ISO which is needed for a specific platform installation and copies it into the created directory.
4. Add information about this iso into `lib/engines/hckinstall/iso.json` (see AutoHCK configuration section).

### AutoHCK configuration

Configure AutoHCK to have all information for building VM images. Edit the next files according to templates present in each file.

1. `lib/engines/hckinstall/iso.json` - contains information about Windows ISO for each HCK/HLK platform. The following fields should be configured:
   - **platform_name** - The platform name should be the same as in the `platforms.json` file.
   - **path** - contains the path relative to `iso_path` option in config file to corresponding ISO image.
   - **windows_image_names** - contains image name from `install.wim` file in ISO. To get a list of available images use the next commands:
      * `dism /get-wiminfo /wimfile:D:\source\install.wim` on Windows.
      * `wiminfo /mnt/source/install.wim` on Linux (wimlib is required).
   - **product_key** - contains a valid key for the corresponding Windows image. Generic keys from MSDN can be used [KMS Client Setup Keys](https://docs.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-R2-and-2012/jj612867(v=ws.11)).

2. `lib/engines/hckinstall/hckinstall.json` - contains the specific configuration for install engine. The following fields should be configured:
   - **hck_setup_scripts_path** - path to HLK-Setup-Scripts repository.
   - **answer_files** (_advanced_) -  list of the unattended answer file for automatic Windows installation. These files are part of HLK-Setup-Scripts repository.
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

To run installation use `install` AutoHCK command-line command. AutoHCK will create 3 images (studio and 2 clients) and perform the installation.

In case when studio image exists, it will be reused. To recreate studio image use `--force` option

### Examples
```
ruby ./bin/auto_hck install -p Win10_2004x86
ruby ./bin/auto_hck install -p Win2019x64 --force
```

## Related information

Automatic installation is performed by using answer files. This is Windows's ability to install and configure the system from the scratch. See the MDSN article for more details:

   - [Automating Windows setup](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup)
   - [Automate Windows configuration](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/update-windows-settings-and-scripts-create-your-own-answer-file-sxs)
