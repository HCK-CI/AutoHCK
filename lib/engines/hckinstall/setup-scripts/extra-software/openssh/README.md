# OpenSSH Server (bundled extra-software package)

AutoHCK installs OpenSSH Server on the studio and every client during image
setup so guests accept password SSH, which the SFTP-based file-transfer backend
(`SshFileManager`) relies on. It is shipped as a built-in extra-software package
rather than a user-provided one, so it is always present on every platform.

## How it is wired

- The package travels to the guest with the setup-scripts template
  (`$EXTRASOFTWAREDIRECTORY\openssh`).
- `install_dest: all` makes the package install on both studio and client; the
  guest-side `extra_software.ps1` installers honour the `all` value.
- `install_time.kit: before` runs it in Stage-Two, before the kit install and
  well before any test-time SFTP probe.
- The arch-matched Win32-OpenSSH zip is downloaded on the AutoHCK host (not the
  guest) by `ExtraSoftwareManager#prepare_bundled_software` and baked into the
  setup ISO, so the guest never needs internet access.

## Install tier ladder (`install-openssh.ps1`)

1. `Install-WindowsFeature OpenSSH-Server` (Windows Server, local payload).
2. `Add-WindowsCapability -Online OpenSSH.Server` (inbox FoD, needs Windows
   Update; fails offline with `0x8024402c`).
3. Bundled Win32-OpenSSH portable zip — universal and offline. The only source
   that covers Server 2016 (no inbox OpenSSH) and ARM64.

After install it configures `PasswordAuthentication yes`, adds an explicit
firewall rule for TCP 22, starts `sshd`, and verifies the service is listening
(non-zero exit fails the build so broken SSH is caught early).

## Pinned Win32-OpenSSH version

`v9.8.1.0p1-Preview` — see `download_url` in each `*-config.json`. When bumping
the pin, update all three arch configs. For fully air-gapped hosts, pre-seed the
matching `OpenSSH-Win64.zip` / `OpenSSH-Win32.zip` / `OpenSSH-ARM64.zip` into
this folder; the downloader skips files that already exist.
