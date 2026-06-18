# Getting Started

This guide covers manual setup of AutoHCK on a Linux host. For an automated installation path, see the [AutoHCK-Installer wiki](https://github.com/HCK-CI/AutoHCK-Installer/wiki).

Return to the [documentation map](Home.md) when you need CLI usage or workspace logging details.

## Overview

AutoHCK orchestrates Windows VMs (via QEMU or physical machines), installs HLK/HCK kits, runs WHQL tests, and collects results. A typical first-time workflow:

1. Install host prerequisites and clone dependency repositories.
2. Configure `config.json` (and optionally `override.json`).
3. Place Windows and kit ISOs on the host and update `iso.json` / kit JSON files as needed.
4. Create VM images: `bin/auto_hck install -p <platform>`.
5. Run tests: `bin/auto_hck test -d <driver> -p <platform> --driver-path <path>`.
6. Verify output under `<workspace_path>/latest/`.

## Automatic installation

See [AutoHCK Installer](https://github.com/HCK-CI/AutoHCK-Installer/wiki) for more details

## Manual installation

AutoHCK runs on a Linux host. The steps below install host tools, clone dependencies, and prepare configuration before you create VM images.

1. Clone this repository. Run these commands from a parent directory of your choice (for example `~/HCK-CI/`)
   ```bash
   git clone https://github.com/HCK-CI/AutoHCK.git
   ```

2. Build QEMU from [source](https://github.com/qemu/qemu) or install using your package manager. On Fedora or RHEL:

   ```bash
   sudo dnf install qemu-kvm qemu-img
   ```

3. Clone the [extra-software](https://github.com/HCK-CI/extra-software) repository as a sibling of `AutoHCK/` (from the same parent directory where you cloned AutoHCK in step 1):

   ```bash
   git clone https://github.com/HCK-CI/extra-software.git
   ```

4. Install Ruby **≥ 3.3.0** (via your package manager or [RVM](https://rvm.io/)). On Fedora or RHEL:

   ```bash
   sudo dnf install ruby ruby-devel gcc make libyaml-devel openssl-devel
   ruby --version   # must be ≥ 3.3.0
   ```

   If `ruby --version` reports below 3.3.0 (common on RHEL 9, Rocky Linux, and AlmaLinux), install Ruby ≥ 3.3.0 with [RVM](https://rvm.io/) or another version manager.


5. Clone **`hckfilters` and `hlkplaylists` inside the AutoHCK repo** at `./filters/` and `./playlists/` (see `hcktest.json`). From the AutoHCK repo root:

   ```bash
   cd AutoHCK
   git clone https://github.com/HCK-CI/hckfilters.git filters
   git clone https://github.com/HCK-CI/hlkplaylists.git playlists
   ```

   Example resulting layout:

   ```
   HCK-CI/                    # parent directory — name is arbitrary
   ├── AutoHCK/
   │   ├── filters/           # → hcktest.json filters_path
   │   └── playlists/         # → hcktest.json playlists_path
   └── extra-software/        # → config.json extra_software
   ```

6. Install Ruby dependencies:

   ```bash
   bundle install
   ```

7. Install host tools used by AutoHCK (QEMU networking, ISO handling, and related scripts). On Fedora or RHEL:

   ```bash
   sudo dnf install -y slirp4netns net-tools ethtool xorriso jq swtpm swtpm-tools
   slirp4netns --version
   which ifconfig ethtool xorriso jq
   command -v swtpm_setup >/dev/null && echo "swtpm OK"
   ```

8. Configure AutoHCK — see [Configuration](#configuration) below (prefer `override.json`).

## Configuration

There are two ways to configure AutoHCK:

### 1. `override.json` (preferred)

`override.json` is gitignored (`/override.*`). AutoHCK deep-merges it into any JSON file it loads, keyed by the target file path (for example `config.json` or `lib/setupmanagers/qemuhck/qemu_machine.json`). Values in the override win over the repository defaults; keys you omit are left unchanged.

Use `--config /path/to/custom.json` to point at a different override file.

#### Create directories

`AUTOHCK_DIR` is the path to your AutoHCK clone. Choose any absolute paths for the data directories below. They do not need to sit under `AUTOHCK_DIR` or follow a particular naming scheme — only the values in `override.json` must match where you actually store files.

```bash
export AUTOHCK_DIR="/path/to/AutoHCK"
export ISO_PATH="/path/to/iso"
export IMAGES_PATH="/path/to/images"
export WORKSPACE_PATH="/path/to/workspace"

mkdir -p "${ISO_PATH}" "${IMAGES_PATH}" "${WORKSPACE_PATH}"
```

Example (AutoHCK and data directories under one parent folder):

```bash
export AUTOHCK_DIR="/home/jane/HCK-CI/AutoHCK"
export ISO_PATH="/home/jane/HCK-CI/iso"
export IMAGES_PATH="/home/jane/HCK-CI/images"
export WORKSPACE_PATH="/home/jane/HCK-CI/workspace"

mkdir -p "${ISO_PATH}" "${IMAGES_PATH}" "${WORKSPACE_PATH}"
```

#### Copy the template

From the AutoHCK repo root:

```bash
cd "${AUTOHCK_DIR}"
cp override.json.example override.json
```

The example ships compiled-QEMU paths and a Win2019 `iso.json` placeholder. Edit every path for your host before running `install` or `test`.

#### Step 1 — `config.json`

| Key | Where to get the value |
|-----|------------------------|
| `iso_path` | Directory for Windows and kit ISO files (`ISO_PATH` above). |
| `extra_software` | Absolute path to the cloned [extra-software](https://github.com/HCK-CI/extra-software) repo (step 3). |
| `workspace_path` | Writable directory for run logs and workspaces (`WORKSPACE_PATH` above). |
| `result_uploaders` | Leave `[]` until you configure [result uploading](#result-uploading). |
| `windows_password` (optional) | Guest Administrator password. Omit to keep the default value from `config.json`. |

```json
"config.json": {
    "iso_path": "/path/to/iso",
    "extra_software": "/path/to/extra-software",
    "workspace_path": "/path/to/workspace",
    "result_uploaders": []
}
```

#### Step 2 — `lib/setupmanagers/qemuhck/qemu_machine.json`

Replace the compiled-QEMU paths from `override.json.example` with your host binaries. On Fedora, `qemu_bin` is usually `/usr/bin/qemu-system-x86_64`; on RHEL / CentOS Stream, `/usr/libexec/qemu-kvm`.

```json
"lib/setupmanagers/qemuhck/qemu_machine.json": {
    "qemu_bin": "/usr/libexec/qemu-kvm",
    "qemu_img_bin": "/usr/bin/qemu-img",
    "ivshmem_server_bin": "",
    "fs_daemon_bin": "/usr/libexec/virtiofsd",
    "fs_daemon_share_path": "/path/to/workspace/fs_share",
    "images_path": "/path/to/images",
    "fs_test_image": "/path/to/images/filesystem_tests_image.qcow2"
}
```

- `qemu_bin` — QEMU system emulator.
- `qemu_img_bin` — `qemu-img` for disk image operations.
- `ivshmem_server_bin` — path to `ivshmem-server`; required only for IVSHMEM driver testing. Leave `""` otherwise. Any compatible `ivshmem-server` binary may be used.
- `fs_daemon_bin` — path to `virtiofsd`; required only for virtiofs driver testing. Leave `""` if you don't have `virtiofsd` and don't want to test the virtiofs driver.
- `fs_daemon_share_path` — host directory shared into guests (often `${WORKSPACE_PATH}/fs_share`).
- `images_path` — qcow2 backing images directory (`IMAGES_PATH` above).
- `fs_test_image` — filesystem test image template; AutoHCK creates it if missing.

#### Complete skeleton (typical manual install)

After editing, a minimal override for the layout in step 5 with distro QEMU on Fedora looks like:

```json
{
    "config.json": {
        "iso_path": "/path/to/iso",
        "extra_software": "/path/to/extra-software",
        "workspace_path": "/path/to/workspace",
        "result_uploaders": []
    },
    "lib/setupmanagers/qemuhck/qemu_machine.json": {
        "qemu_bin": "/usr/bin/qemu-system-x86_64",
        "qemu_img_bin": "/usr/bin/qemu-img",
        "ivshmem_server_bin": "",
        "fs_daemon_bin": "/usr/libexec/virtiofsd",
        "fs_daemon_share_path": "/path/to/workspace/fs_share",
        "images_path": "/path/to/images",
        "fs_test_image": "/path/to/images/filesystem_tests_image.qcow2"
    },
    "lib/engines/hckinstall/iso.json": {}
}
```

Fill in `iso.json` when you follow [Image Installation](Image-Installation.md) (before `bin/auto_hck install`).

#### Validate

```bash
jq . "${AUTOHCK_DIR}/override.json" > /dev/null && echo "JSON valid"
jq -r '."config.json".extra_software' "${AUTOHCK_DIR}/override.json"
test -x "$(jq -r '."lib/setupmanagers/qemuhck/qemu_machine.json".qemu_bin' "${AUTOHCK_DIR}/override.json")" && echo "qemu OK"
test -x "$(jq -r '."lib/setupmanagers/qemuhck/qemu_machine.json".qemu_img_bin' "${AUTOHCK_DIR}/override.json")" && echo "qemu-img OK"
FS_DAEMON="$(jq -r '."lib/setupmanagers/qemuhck/qemu_machine.json".fs_daemon_bin' "${AUTOHCK_DIR}/override.json")"
[ -n "$FS_DAEMON" ] && test -x "$FS_DAEMON" && echo "virtiofsd OK"
```

### 2. Direct edit of JSON files

Alternatively, edit each configuration JSON file in the repository:

* `config.json` is the general configuration file which holds the paths to the dependencies stated above.
* `lib/engines/hcktest/hcktest.json` is the specific configuration file for the test engine.
* `lib/engines/hcktest/platforms/<platform>.json` are a set of files with operating systems images configuration.
* `lib/engines/hcktest/drivers/<driver>.json` are a set of files of drivers information for testing.
* `lib/engines/hckinstall/iso.json` list of ISO with information for unattended VM installation.
* `lib/engines/hckinstall/hckinstall.json` is the specific configuration file for the install engine.
* `lib/engines/hckinstall/kits/<kit>.json` list of HCK/HLK kits.

## Microsoft HCK filters

Filters are fixes for problematic tests. See [Microsoft HLK Filters](https://docs.microsoft.com/en-us/windows-hardware/test/hlk/user/windows-hardware-lab-kit-filters).

If you followed [step 5](#manual-installation), `filters/UpdateFilters.sql` is already in place. Otherwise clone [HCK-CI/hckfilters](https://github.com/HCK-CI/hckfilters) to `filters/` at the AutoHCK repo root (path configured in `hcktest.json` → `filters_path`).

## Microsoft HLK playlists

If you followed [step 5](#manual-installation), `playlists/` is already in place. Otherwise clone [HLK Playlists](https://github.com/HCK-CI/hlkplaylists) to `playlists/` at the AutoHCK repo root (path configured in `hcktest.json` → `playlists_path`). See also [Download Windows Hardware Compatibility Playlist](https://learn.microsoft.com/en-us/windows-hardware/test/hlk/#download-windows-hardware-compatibility-playlist). AutoHCK selects the appropriate XML playlist for the kit/platform.

## Images installation

See [Image Installation](Image-Installation.md) for ISO preparation, answer files, kit configuration, UEFI ISO patching, and the `install` command.

## Result uploading

AutoHCK supports uploading the results of the tests, (logs, test results and the hckx\hlkx package file), using the supported uploaders by configuring the `result_uploaders` array in `config.json` to the desired uploaders for AutoHCK to use, for example, to use dropbox:

```
    "studio_username": "Administrator",
    "studio_password": "your_password",
 -> "result_uploaders": [ "dropbox" ]
}
```

### Supported result uploaders

#### 1. Dropbox

To use dropbox result uploading capabilities you will need to create an auth2 token
1. go to https://www.dropbox.com/developers/apps and click on 'Create app'.
2. select 'Dropbox API', 'Full Dropbox' access type and give it a unique name.
3. copy the Client ID and Client Secret and use them as environment variables with `export AUTOHCK_DROPBOX_CLIENT_ID=<id>` and `export AUTOHCK_DROPBOX_CLIENT_SECRET=<secret>`.
4. run `ruby ./bin/auto_hck config`, navigate to URL and give access rights to proper Dropbox account.

#### 2. (Other result uploaders are in working progress)

## Github integration

When specifying a pull request AutoHCK can mark test results on GitHub and link to the dropbox logs folder.
to do that you will need to create a personal access token.
1. go to https://github.com/settings/tokens and click on 'Generate new token'
2. give it a name, select: repo:status, and click 'Generate token'
3. set the new environment variable for your username and token with `export AUTOHCK_GITHUB_LOGIN=<LOGIN>` and `export AUTOHCK_GITHUB_TOKEN=<TOKEN>`
