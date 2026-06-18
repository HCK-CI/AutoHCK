# AutoHCK image creation

AutoHCK automates HCK/HLK testing, including unattended Windows installation and HLK kit setup on studio and client VMs.

See [Getting Started](Getting-Started.md) for host prerequisites and [Home](Home.md) for the `install` command overview.

## Manual installation

The install engine ships PowerShell setup scripts under `lib/engines/hckinstall/setup-scripts/`. At run time it copies that tree into the workspace (for example as `hck-setup-scripts`) and builds setup ISOs from there. Unattend templates and optional local kit/driver layouts are described in [Bundled install engine directories](#bundled-install-engine-directories) below.

For more context on the original upstream workflow, see [HLK-Setup-Scripts](https://github.com/HCK-CI/HLK-Setup-Scripts).

Finished qcow2 images are stored under `images_path` in `lib/setupmanagers/qemuhck/qemu_machine.json`. 

## Automatic installation preparation

### Windows ISO preparation

If you configured `iso_path` in [Getting Started](Getting-Started.md#1-overridejson-preferred), the directory already exists. Otherwise create it and set `config.json` → `iso_path` first.

1. **Obtain a Windows ISO** — use an ISO you already have, or download one from Microsoft ([Evaluation Center](https://www.microsoft.com/evalcenter/), [Software Download](https://www.microsoft.com/en-in/software-download)).

2. **Pick the right Windows release** for the platform you will install (`-p <platform>`). AutoHCK installs two kinds of VMs — a **studio** (HLK server) and **clients** (test machines). Each needs a Windows ISO entry in `iso.json`:
   - **Clients** — see `client_iso` in `lib/engines/hcktest/platforms/<platform>.json`.
   - **Studio** — see `studio_platform` in `lib/engines/hckinstall/kits/<kit>.json` (use the `kit` named in the platform file).

   Example: for `-p Win2019x64`, both point to `Win2019x64`, so you need a **Windows Server 2019** ISO with an `iso.json` entry under that name.

3. **Copy the ISO into `iso_path`.** Keep the original filename; you will use the same name in `iso.json` → `path` ([AutoHCK configuration](#autohck-configuration)).


### Bundled install engine directories

These paths live next to the install engine under `lib/engines/hckinstall/`:

#### Answer files (`answer-files/`)

Templates for unattended Windows setup. AutoHCK selects and processes them when building images; see `hckinstall.json` → `answer_files`.

- **autounattend** — drives Windows setup. Placeholders:
  - `@WINDOWS_IMAGE_NAME@` — image name from `install.wim` (e.g. `wimlib-imagex info install.wim` on Linux, or `dism /get-wiminfo` on Windows).
  - `@PRODUCT_KEY_XML@` — product key content for that image, substituted into the `<ProductKey>` element.
  - Two template variants: `autounattend.xml.uefi.in` (UEFI, GPT) and `autounattend.xml.bios.in` (BIOS, MBR).

- **unattend** — OOBE / post-setup. Placeholder:
  - `@HOST_TYPE@` — `studio` or `client`.

Base names in `hckinstall.json` are `autounattend.xml` and `unattend.xml`; the engine resolves the correct `.uefi` / `.bios` / `.in` files from `answer-files/`.

#### Kit installers

Each HLK/HCK kit has its own JSON file under `lib/engines/hckinstall/kits/<kit>.json` (for example `HLK11_24H2.json`). Kit ISO installers can also be placed under `iso_path` when downloaded locally (see download URLs in each kit file).

### Windows ISO preparation for installation in UEFI mode

When UEFI firmware (not BIOS) is used, the Windows installer prompts to press any key to boot from CD/DVD. AutoHCK cannot send that key automatically.

So you should patch ISO and replace UEFI boot loader code. By default, ISO uses the EFI boot code from efisys.bin. There is also an efisys_noprompt.bin boot code that skips the prompt step.

Please use the following commands to create a patched ISO. Replace `original.iso` with your downloaded Windows ISO; `-o new.iso` writes the patched copy (use any output filename — it must match the `path` in `iso.json`).

Using mkisofs:

```bash
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
umount /mnt
```

Using xorriso:

```bash
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

Configure AutoHCK with the information needed to build VM images. Edit the following files according to the templates in each file.

1. `lib/engines/hckinstall/iso.json` holds information about the Windows ISO for each HCK/HLK platform. Each platform entry uses the following fields:
   - **platform_name** (top-level key) must match the name referenced in platform configuration files via the `client_iso` field, or in kit JSON files via the `studio_platform` field.
   - **path** is the path relative to `iso_path` in `config.json` to the corresponding ISO file.
   - **studio** (required for platforms used as studio VMs) contains studio-specific settings:
      * **windows_image_names** is the image name from `install.wim` in the ISO for the studio VM.
      * **product_key** is a valid product key for the studio Windows image.
   - **client** (required for platforms used as client VMs) contains client-specific settings:
      * **windows_image_names** is the image name from `install.wim` in the ISO for the client VM.
      * **product_key** is a valid product key for the client Windows image.

   **Note:** Server platforms (e.g. `Win2022x64`, `Win2019x64`) typically require **both** `studio` and `client` sections because they can be used in either role. Client-only platforms (e.g. `Win10_22H2x86`) require only the `client` section.

   To list available Windows image names from an ISO:
   * On Windows, run `dism /get-wiminfo /wimfile:D:\sources\install.wim`.
   * On Linux, install [wimlib](https://wimlib.net/) first, then mount the ISO and list image names. Replace `/path/to/windows.iso` in the command with your ISO file (for example, a file under `iso_path`). Some ISOs use `sources/install.esd` instead of `install.wim`; substitute that path if needed (`wimlib-imagex` supports both).

     ```bash
     sudo mkdir -p /mnt/winiso
     sudo mount -o loop,ro /path/to/windows.iso /mnt/winiso
     wimlib-imagex info /mnt/winiso/sources/install.wim | grep '^Name:' | sed 's/^Name:[[:space:]]*//'
     sudo umount /mnt/winiso
     ```


   Generic product keys can be found at [KMS Client Activation Keys](https://learn.microsoft.com/en-us/windows-server/get-started/kms-client-activation-keys).

   **Example configurations:**

   * Server platform with both studio and client sections:

     ```json
     {
       "Win2022x64": {
         "path": "en-us_windows_server_2022_x64_dvd_620d7eac_uefi.iso",
         "studio": {
           "windows_image_names": "Windows Server 2022 SERVERSTANDARD",
           "product_key": "AAAAA-AAAAA-AAAAA-AAAAA-AAAAA"
         },
         "client": {
           "windows_image_names": "Windows Server 2022 SERVERDATACENTER",
           "product_key": "AAAAA-AAAAA-AAAAA-AAAAA-AAAAA"
         }
       }
     }
     ```

   * Client-only platform with just client section:

     ```json
     {
       "Win10_22H2x86": {
         "path": "en-us_windows_10_business_editions_version_22h2_updated_march_2025_x86_dvd_a4d0e05b.iso",
         "client": {
           "windows_image_names": "Windows 10 Enterprise",
           "product_key": "BBBBB-BBBBB-BBBBB-BBBBB-BBBBB"
         }
       }
     }
     ```

2. `lib/engines/hckinstall/hckinstall.json` contains settings for the install engine. You may override the following fields:
   - **answer_files** (_advanced_) is a list of answer file *base names* (without `.in` or disk-layout suffixes) used for unattended Windows installation. Templates live under `lib/engines/hckinstall/answer-files/`; see the Answer files subsection under [Bundled install engine directories](#bundled-install-engine-directories).
   - **install_timeout** (_advanced_) is the timeout in seconds before an install is treated as failed. It covers the studio and client flows together.

   During `install`, AutoHCK copies bundled scripts, merges extra software and generated `args.ps1`, builds `setup-studio.iso` / `setup-client.iso`, and attaches them to the VMs. HLK kit **ISO** installers are stored under `iso_path` (for example `HLK11_24H2Setup.iso`) when downloaded so later runs can reuse them; **EXE** installers are downloaded into the workspace copy for each run.

3. `config.json` holds the general AutoHCK configuration. Configure the following field:
   - **iso_path** is the absolute path to the directory where ISOs are stored.

4. `lib/engines/hckinstall/kits/<kit>.json` defines one HCK/HLK kit per file (for example `HLK2022.json`, `HLK11_25H2.json`). The **`kit`** field in `lib/engines/hcktest/platforms/<platform>.json` must match the filename (without `.json`). Each kit file uses these fields:
   - **name** is the kit identifier (same as the filename stem).
   - **download_url** is the URL used to download the kit online installer.
   - **sha256** is the expected installer checksum.
   - **studio_platform** is the platform name for the studio VM Windows image. It must exist in `iso.json` with a `studio` section, and in `lib/engines/hcktest/platforms/`.
   - **extra_software** lists optional packages from the extra-software repository that are installed during studio setup.

5. `lib/engines/hcktest/platforms/<platform>.json` links a test platform to a kit, client ISO, backing images, and setup manager. The **`kit`** field must match a file in `lib/engines/hckinstall/kits/`, and **`client_iso`** must match a top-level key in `iso.json`.

6. `lib/setupmanagers/<setup_manager>/<setup_manager>.json` contains settings for a setup manager backend. Edit the file for the backend you use. Existing configs are:
   - `lib/setupmanagers/physhck/physhck.json`
   - `lib/setupmanagers/qemuhck/qemu_machine.json`

Notes:
   - Please do **not** edit any advanced configurations if you don't understand what it does!
   - All config files with generic config are present in the repository, you can use them as templates.

### Extra software installation

The `extra_software` option can be set in the following files:
  - `lib/engines/hcktest/drivers/<driver>.json` — packages listed here are installed in test mode only.
  - `lib/engines/hckinstall/kits/<kit>.json` — packages listed here are installed in install mode only.
  - `lib/engines/hcktest/platforms/<platform>.json` — packages listed here are installed in both install and test modes.

According to the file, the software is installed during image creation (install mode) or during driver testing (test mode).

## Automatic installation

AutoHCK creates a studio image and client images for the selected platform (typically two clients). If a studio image already exists, it is reused unless `--force` is specified.

```bash
bin/auto_hck install -p Win10_2004x86_bios
bin/auto_hck install -p Win2019x64 --force
```

**Verify success:** install log in `<workspace_path>/hckinstall/<platform>/<timestamp>/<platform>.log`; backing qcow2 files under `qemu_machine.json` → `images_path` match names in the platform JSON.

## Related information

Automatic installation is performed by using answer files. This is Windows's ability to install and configure the system from scratch. See the MSDN articles for more details:

- [Automating Windows setup](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup)
- [Automate Windows configuration](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/update-windows-settings-and-scripts-create-your-own-answer-file-sxs)
