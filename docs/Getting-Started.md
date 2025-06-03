# Getting Started

There are not so few steps needed to install and set up AutoHCK, First of all, clone AutoHCK and follow the instruction below:

## Automatic installation

See [AutoHCK Installer](https://github.com/HCK-CI/AutoHCK-Installer/wiki) for more details

## Manual installation

  1. Build QEMU from [source](https://github.com/qemu/qemu) or install using your package manager.
  1. `git clone https://github.com/HCK-CI/HLK-Setup-Scripts` - AutoHCK will use it as a dependency for image creation.
  1. `git clone https://github.com/HCK-CI/extra-software` - AutoHCK will use it as a dependency for image creation.
  1. `git clone https://github.com/HCK-CI/toolsHCK` - AutoHCK will use it as a dependency for HLK automation in Guest OS.
  1. Install Ruby version 3.1.0 or 3.3.0. Using [RVM](https://rvm.io/) or your package manager.
  1. `cd AutoHCK`,  `bundler install` - AutoHCK ruby dependencies.
  1. Install [slirp4netns](https://github.com/rootless-containers/slirp4netns) v0.4.0 or newer.

  1. `git clone https://github.com/HCK-CI/hckfilters` - Filters are fixes for problematic tests.
  1. `git clone https://github.com/HCK-CI/hlkplaylists` - To run HLK tests with the latest Microsoft compatibility playlist.
  1. Update configuration files

## Configuration

There are two way to configure AutoHCK:

  1. Create `override.json` based on `override.json.example` (preferred)
  2. Edit each configurations JSON files:
     * `config.json` is the general configuration file which holds the paths to the dependencies stated above.
     * `lib/engines/hcktest/hcktest.json` is the specific configuration file for the test engine.
     * `lib/engines/hcktest/platforms/<platform>.json` are set of file with operations systems images configuration.
     * `lib/engines/hcktest/drivers/<driver>.json` are set of file of drivers information for testing.
     * `lib/engines/hckinstall/iso.json` list of ISO with information for unattended VM installation.
     * `lib/engines/hckinstall/hckinstall.json` is the specific configuration file for the install engine.
     * `lib/engines/hckinstall/kit.json` list of HCK/HLK kits.

## Additional information

### Microsoft HCK filters

Filters are fixes for problematic tests, read more at: [Microsoft HLK Filters](https://docs.microsoft.com/en-us/windows-hardware/test/hlk/user/windows-hardware-lab-kit-filters)
To run tests with applied filters automatically, get a copy of `UpdateFilters.sql` from [HCK-CI/hckfilters](https://github.com/HCK-CI/hckfilters) and place them inside AutoHCK at `filters/UpdateFilters.sql` .

### Microsoft HLK playlists

To run HLK tests with the latest Microsoft compatibility playlist clone [HLK Playlists](https://github.com/HCK-CI/hlkplaylists) inside AutoHCK and rename the directory to playlists, once it's there AutoHCK will look for the right XML playlist file and apply it to the tests.

## Images installation

See [ImageInstallation](Image-Installation.md) for more details

## Result uploading

AutoHCK supports uploading the results of the tests, (logs, test results and the hckx\hlkx package file), using the supported uploaders by configuring the array field "result_uploader" in the `config.json` file to the desired uploaders for AutoHCK to use, for example, to use dropbox:

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
