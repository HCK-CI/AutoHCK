# Functest Engine

The functest engine runs JSON-driven functional tests against a Windows client VM with no HLK Studio required. It is designed for testing driver behavior independently of the full HLK/HCK certification pipeline.

## Running functest

```
./bin/auto_hck [common options] functest [functest options]
```

### Functest options

| Option | Description |
|---|---|
| `-p`, `--platform <name>` | Platform name (maps to `lib/engines/hcktest/platforms/<name>.json`) |
| `-d`, `--drivers <list>` | Comma-separated driver short names (maps to `lib/engines/hcktest/drivers/<name>.json`) |
| `--driver-path <path>` | Host path to the driver package directory; required when drivers are configured, unless `--test-binaries-path` is used instead (see [Device-only testing](#device-only-testing) below) |
| `--test-binaries-path <path>` | Host path to binaries the test needs (e.g. an installer); available to test steps as `@test_binaries_path@` |
| `--category <suite>` | Run a named test suite; `<suite>` is the suite name from `lib/engines/functest/tests/suites/<suite>.json` |
| `--testcase <names>` | Comma-separated list of test case names to run (e.g. `driver_sign_check,balloon/balloon_service`) |
| `--select-test-names <file>` | Path to a text file (one test name per line); only tests whose name appears in the file are kept |
| `--reject-test-names <file>` | Path to a text file (one test name per line); tests whose name appears in the file are skipped. Overrides the suite's own `reject_test_names`, if any. |
| `--manual` | Run tests normally, then pause before VM teardown and drop into an IRB shell for manual inspection |
| `--auto-manual` | Same as `--manual`, but only pauses if any test failed or an exception occurred |
| `--extensions <list>` | Comma-separated list of extension names to activate (e.g. `driver_verifier`); each maps to `lib/engines/hcktest/extensions/<name>.json` |

Exactly one of `--category` or `--testcase` is required. All common options (`--verbose`, `--config`, `--id`, etc.) apply as documented in [Home](Home.md).

`--select-test-names`/`--reject-test-names` are the same flags used by the `hcktest` engine; the "test name" they match against is the test case identifier as written in `--testcase`/a suite's `tests` array (e.g. `balloon/balloon_service`), not the `name` field inside the test case's own JSON.

### Examples

#### Run a test suite

```bash
./bin/auto_hck functest \
  -p Win2025x64_gui \
  -d Balloon \
  --driver-path /path/to/balloon/driver \
  --category balloon_driver_tests
```

#### Run individual test cases

```bash
./bin/auto_hck functest \
  -p Win2025x64_gui \
  -d Balloon \
  --driver-path /path/to/balloon/driver \
  --testcase driver_sign_check,driver_update
```

For test cases in subdirectories, use the relative path from `lib/engines/functest/tests/cases/` as the name:

```bash
--testcase balloon/balloon_service,driver_sign_check
```

#### Narrow down a suite

Given a suite with many tests, run only a subset of them, or skip a few, without editing the suite file or hand-listing everything via `--testcase`:

```bash
./bin/auto_hck functest \
  -p Win2025x64_gui \
  -d Balloon \
  --driver-path /path/to/balloon/driver \
  --category balloon_driver_tests \
  --select-test-names /path/to/select_names.txt
```

```bash
./bin/auto_hck functest \
  -p Win2025x64_gui \
  -d Balloon \
  --driver-path /path/to/balloon/driver \
  --category balloon_driver_tests \
  --reject-test-names /path/to/reject_names.txt
```

Where each file contains one test name per line, e.g.:

```
balloon/balloon_service
driver_update
```

### Device-only testing

Pass `--test-binaries-path <path>` without `--driver-path` to attach configured devices (`-d`) while skipping
driver installation. The content of `--test-binaries-path` is uploaded to the client VM automatically (to
`C:\AutoHCK\test_binaries`). The host path is exposed to test steps as `@test_binaries_path@`, and the
uploaded guest path as `@test_binaries_dir@`.

```bash
./bin/auto_hck functest \
  -p Win2025x64_gui \
  -d Balloon \
  --test-binaries-path /path/to/installer \
  --testcase <test-name>
```

| `--driver-path` | `--test-binaries-path` | Result |
|---|---|---|
| set | any | Normal driver installation |
| nil | set | Driver installation skipped; devices still attached |
| nil | nil | Error: `--driver-path is required when drivers are configured` |

## Directory Layout

```
lib/engines/functest/
  functest.json                   Engine configuration
  tests/
    suites/                       Test suite definitions  (*.json)
    cases/                        Individual test cases   (*/*.json or *.json)
    scripts/                      Scripts used by guest_run_file (PowerShell) and host_run_file (shell) steps
```

## Engine Configuration

`lib/engines/functest/functest.json` controls engine-level defaults:

| Field | Description |
|---|---|
| `name` | Engine identifier |
| `description` | Human-readable description |
| `test_definitions_path` | Root directory for test case and suite JSON files |
| `default_timeout` | Default step timeout in seconds (used when a step does not specify `timeout`) |
| `result_format` | Output formats for results (e.g. `["json", "junit"]`) |

## Extensions

Extensions inject commands around test cases without modifying test case JSON files. They are stored in `lib/engines/hcktest/extensions/` and activated via `--extensions <name>` (comma-separated for multiple).

Execution order per test:

```
extension pre_test_commands   (e.g. enable DV + reboot)
  test pre_test_commands
    test_steps
  test cleanup
extension post_test_commands  (e.g. disable DV + reboot)
```

A failure in extension `pre_test_commands` marks the test failed. A failure in `post_test_commands` is logged as a warning only.

### Extension JSON format

| Field | Description |
|---|---|
| `extra_software` | Packages to pre-install on the guest before any tests run |
| `tests_config` | Array of per-test hook entries |

Each `tests_config` entry:

| Field | Description |
|---|---|
| `tests` | Regex patterns matched against the test case `name` field. Use `[".*"]` for all tests. |
| `pre_test_commands` | Steps run before each matching test |
| `post_test_commands` | Steps run after each matching test |

> `tests` matches the `name` field inside the test case JSON, **not** the path used in a suite. A test at `balloon/balloon_service` has `name` = `balloon_service`.

Multiple extensions can be listed with `--extensions EXT1,EXT2`. The order follows the CLI argument order — EXT1 pre commands run before EXT2 pre commands, and the same for post commands.

### Available extensions

| Name | Description |
|---|---|
| `driver_verifier` | Enables Driver Verifier (standard flags) before each test and disables it after, with a reboot on each side. |

---

## Test Suite Format

A suite is an ordered list of test case references, plus optional metadata. Suites are stored in `lib/engines/functest/tests/suites/`.

### Suite Fields

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Suite name; used in log output |
| `description` | No | Human-readable description |
| `test_system_ref` | No | Reference to an issue or ticket |
| `tests` | Yes | Ordered list of test case names to execute |
| `requirements.drivers` | No | Informational only — not enforced at runtime |
| `requirements.platforms` | No | Informational only — not enforced at runtime |
| `reject_test_names` | No | Test case names to always skip when running this suite. Ignored if `--reject-test-names` is passed on the CLI. |

### Example

See [`lib/engines/functest/tests/suites/balloon_driver_tests.json`](../lib/engines/functest/tests/suites/balloon_driver_tests.json) for a full example.

```json
{
    "name": "balloon_driver_tests",
    "description": "Driver qualification tests for balloon",
    "test_system_ref": "VIRT-250",
    "tests": [
        "driver_sign_check",
        "balloon/balloon_service",
        "driver_update"
    ],
    "requirements": {
        "drivers": [ "Balloon" ],
        "platforms": [ "Win10x64", "Win2019x64" ]
    }
}
```

## Test Case Format

A test case defines an ordered sequence of steps and optional cleanup steps. Cases are stored in `lib/engines/functest/tests/cases/`.

### Test Case Fields

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Test case name; shown in results and log output |
| `description` | No | Human-readable description |
| `test_system_ref` | No | Reference to an issue or ticket |
| `extra_software` | No | List of software packages to install on the guest before any tests run |
| `pre_test_commands` | No | Steps run before test start; a failure aborts remaining steps |
| `cycles` | No | Allow to repeat test_steps several times |
| `test_steps` | Yes | Ordered array of step objects; a failure aborts remaining steps |
| `cleanup` | No | Steps run after test completes (pass or fail); errors here do not change test status |
| `clients` | No | Client ids (e.g. `[1, 2]`) this test case needs booted. Default: `[1]`. See [Multi-Client Support](#multi-client-support). |
| `clean_boot` | No | If `true`, throw away the client's current VM state and boot fresh from the clean base image before running `test_steps`. Can't be used together with `boot_from_snapshot_tag`. Default: `false`. |
| `boot_from_snapshot_tag` | No | Name of a snapshot tag saved earlier in the suite by another test's `save_snapshot_as`. Boots from that tag before running `test_steps`. Can't be used together with `clean_boot`. |
| `save_snapshot_as` | No | After `test_steps` pass, save the VM's disk as a snapshot tag with this name, then reboot from it. Other tests can later boot from this tag using `boot_from_snapshot_tag`. |

### VM Snapshots

`clean_boot`, `boot_from_snapshot_tag`, and `save_snapshot_as` let tests in a suite share VM state, so a later test can reuse what an earlier one set up instead of doing it again:

| Order | Test | Field | Effect |
|---|---|---|---|
| 1 | `test_a` | `save_snapshot_as: "state_x"` | Runs as normal; if it passes, saves the VM's disk as tag `state_x`. |
| 2 | `test_b` | `boot_from_snapshot_tag: "state_x"` | Boots from tag `state_x` instead of continuing from `test_a`. |
| 3 | `test_c` | `boot_from_snapshot_tag: "state_x"` | Also boots from `state_x`, separately from `test_b`. |
| 4 | `test_d` | `clean_boot: true` | Ignores all tags; boots from the clean base image. |
| 5 | `test_e` | *(none)* | No change; just keeps using the VM as `test_d` left it. |

A tag has to be created by an earlier test's `save_snapshot_as` before another test can use it with `boot_from_snapshot_tag`. Using a tag that doesn't exist yet fails the test with an error.

Tag files (`*-snapshot-<tag>.qcow2` in the workspace directory) are never deleted automatically, whether the suite passes or fails. You can always boot from one later by hand to check the state it holds.

### Example

See [`lib/engines/functest/tests/cases/driver_sign_check.json`](../lib/engines/functest/tests/cases/driver_sign_check.json) for a full example.

```json
{
    "name": "driver_sign_check",
    "description": "Verify the installed driver .sys is digitally signed",
    "test_system_ref": "VIRT-200",
    "test_steps": [ ... ],
    "cleanup": [ ... ]
}
```

## Step Types

> Each step object must have **exactly one** step-type field (`guest_run`, `guest_run_file`, `guest_reboot`, `host_run`, `host_run_file`, `files_action`, `qmp_command`, `qmp_wait_event`, `barrier`, `set_variable`). All other fields are optional modifiers.

### Common Step Fields

| Field | Description |
|---|---|
| `desc` | Human-readable description; logged and shown in results. |
| `timeout` | Step timeout in seconds; overrides the engine default of 300s. |
| `ignore_errors` | If `true`, a failure in this step does not abort the test. Useful for optional steps in `test_steps`. Default: `false`. |
| `variables` | Maps `@placeholder@` strings to existing context variable names for extra substitution within this step. |
| `capture_output` | Name of a variable to store the step's output in, e.g. `"capture_output": "driver_version"` makes it available as `@driver_version@` later. Supported by `guest_run`/`guest_run_file`, `qmp_command`, `qmp_wait_event`. On a multi-client step, only the primary target's output is captured. |
| `expected_output_contains` | The step fails if the output does not contain this string. Only for `guest_run`/`guest_run_file`. Checked against every client the step ran on. |
| `expected_output_matches` | The step fails if the output does not match this regex. Only for `guest_run`/`guest_run_file`. Checked against every client the step ran on. |
| `clients` | Client ids (e.g. `[2]`) this step targets. Applies to `guest_run`/`guest_run_file`, `guest_reboot`, `files_action`, `qmp_command`, `qmp_wait_event`; `host_run`/`host_run_file` always run once on the host regardless. Omitted/empty broadcasts to every client booted for the test case. See [Multi-Client Support](#multi-client-support). |

---

### `guest_run`

Runs an inline command on the client VM via WinRM.

```json
{
    "desc": "Stop balloon service",
    "guest_run": "Stop-Service BalloonService -Force; Write-Output 'done'",
    "expected_output_contains": "done",
    "timeout": 30
}
```

---

### `guest_run_file`

Reads a local script file and executes its content on the client VM. The path is relative to the AutoHCK root.

```json
{
    "desc": "Verify driver is signed",
    "guest_run_file": "lib/engines/functest/tests/scripts/verify_driver_signed.ps1",
    "expected_output_contains": "PASS:",
    "timeout": 60
}
```

---

### `guest_reboot`

Reboots the client VM and waits for it to come back online before proceeding.

```json
{
    "desc": "Reboot to apply driver installation",
    "guest_reboot": true
}
```

---

### `host_run`

Runs a command on the host machine running AutoHCK. The command runs with the workspace as its working directory, so relative paths resolve inside the workspace. Pass/fail is determined solely by the command's exit code (non-zero exit fails the step); `capture_output`/`expected_output_contains`/`expected_output_matches` are not supported here.

```json
{
    "desc": "Extract driver package on host",
    "host_run": "unzip /tmp/driver.zip -d /tmp/driver_extracted"
}
```

---

### `host_run_file`

Reads a local script file and runs its content on the host machine running AutoHCK, the host-side equivalent of `guest_run_file`. The path is relative to the AutoHCK root. Like `host_run`, the script runs with the workspace as its working directory and pass/fail is determined by the exit code.

Note: Only Bash scripts are supported; shebang lines are not honored.

---

### `files_action`

Transfer files or directories between the host and the client VM.

```json
{
    "desc": "Upload driver package to VM",
    "files_action": [
        {
            "local_path": "@driver_path@",
            "remote_path": "C:\\AutoHCK\\driver_pkg",
            "direction": "local-to-remote"
        }
    ]
}
```

#### File Operation Fields

| Field | Required | Description |
|---|---|---|
| `local_path` | Yes | Path to the file or directory on the host. |
| `remote_path` | Yes | Path to the file or directory on the client VM. |
| `direction` | No | `local-to-remote` to upload, `remote-to-local` to download. Default: `remote-to-local` |
| `move` | No | If `true`, delete the source after transfer. Default: `false` (copy). |
| `allow_missing` | No | If `true`, skip silently when the source does not exist. Default: `false` (raise error). |

---

### `qmp_command`

Send a QEMU Monitor Protocol (QMP) command to the client VM at the hypervisor level. The JSON mirrors the QMP wire format exactly.

```json
{
    "desc": "Balloon VM memory to 512 MB",
    "qmp_command": {
        "execute": "balloon",
        "arguments": { "value": 536870912 }
    }
}
```

#### `qmp_command` Fields

| Field | Required | Description |
|---|---|---|
| `execute` | Yes | QMP command name (e.g. `"balloon"`, `"query-balloon"`) |
| `arguments` | No | Command arguments as a JSON object |

---

### `qmp_wait_event`

Blocks until one of the given QEMU events is received from the client VM. `events` is a list of event names; this returns as soon as any one of them is seen — useful for devices that may emit one of several events depending on guest state:

```json
{
    "desc": "Wait for balloon change event",
    "qmp_wait_event": {
        "events": ["BALLOON_CHANGE"],
        "timeout": 30
    }
}
```

```json
{
    "desc": "Wait for a guest crash event from the pvpanic device",
    "qmp_wait_event": {
        "events": ["GUEST_PANICKED", "GUEST_CRASHLOADED"],
        "timeout": 120
    }
}
```

#### `qmp_wait_event` Fields

| Field | Required | Description |
|---|---|---|
| `events` | Yes | Array of QMP event names to wait for (e.g. `["BALLOON_CHANGE"]`); returns as soon as any one occurs |
| `timeout` | No | Maximum seconds to wait. Defaults to the engine `default_timeout`. |

> Use `capture_output` to record which event actually fired (the full event payload, including its `event` name, is captured) so a later step can branch on it.

---

### `barrier`

A named synchronization point. It only logs the barrier name and does nothing else.

---

### `set_variable`

Sets one or more context variables directly. Values support `@variable@` substitution.

```json
{
    "desc": "Set hotplug disk number",
    "set_variable": { "disk_number": "2" }
}
```

The variable is then available as `@disk_number@` in all subsequent steps. Overwriting an existing variable is allowed and logged.

Multiple variables can be set in a single step:

```json
{
    "desc": "Set test parameters",
    "set_variable": { "disk_number": "2", "bus_slot": "0x04" }
}
```

---

## Multi-Client Support

A test case can declare multiple clients via its top-level `clients` field, and a step can target one of them via its own `clients` field. Both use plain client ids (`1`, `2`, ...), mapped by position to the platform JSON's `clients` map — id `1` is its 1st entry, `2` its 2nd, etc. That entry's `name` (`CL1`, etc.) is the actual VM.

```json
{
    "name": "multi_client_example",
    "clients": [1, 2],
    "test_steps": [
        {
            "desc": "Runs only on client 1",
            "clients": [1],
            "guest_run": "Write-Output 'hello from client 1'"
        },
        {
            "desc": "Runs on every client booted for this test case",
            "guest_run": "Write-Output 'hello from everyone'"
        }
    ]
}
```

- `clients` defaults to `[1]`, so existing single-client tests are unaffected. `FunctestEngine` boots the union of `clients` across every selected test, once, up front.
- A step's `clients` must be a subset of its test case's `clients`, and each id's corresponding role (`"c<id>"`) must be declared in the platform JSON — otherwise the step fails.
- `capture_output` stores only the primary target's output; `expected_output_contains`/`expected_output_matches` are checked against every machine the step ran on.

---

## Variable Substitution

Variables are substituted in `desc`, `guest_run`, `guest_run_file` (script body), `host_run`, `host_run_file` (script body), `local_path`, and `remote_path` fields using the `@variable_name@` syntax.

### Built-in Variables

These are populated automatically from CLI arguments and driver configuration:

| Variable | Description |
|---|---|
| `@driver_path@` | Local path to the driver package directory (`--driver-path` CLI option) |
| `@driver_module@` | Driver module name derived from the INF filename (e.g. `balloon` from `balloon.inf`). Not set for `no-drv` drivers, which have no INF. |
| `@driver_inf@` | INF filename of the driver (e.g. `balloon.inf`). Not set for `no-drv` drivers, which have no INF. |
| `@driver_name@` | Full driver name as defined in the driver JSON configuration |
| `@test_binaries_path@` | Local host path to test binaries content (`--test-binaries-path` CLI option); see [Device-only testing](#device-only-testing) |
| `@test_binaries_dir@` | Guest path where `--test-binaries-path` content was uploaded (`C:\AutoHCK\test_binaries`) |
| `@spare_pcie_root_port_N@` (`N` = `0`, `1`, ...) | Bus id of the Nth spare, empty `pcie-root-port` allocated at boot via `--pcie-spare-root-ports <N>` (e.g. `@spare_pcie_root_port_0@` → `root2.0`). The max value of `N` depends on QEMU |
| `@client_id@` | Zero-padded client id (e.g. `01`, `02`). Varies per target machine in `guest_run`/`guest_run_file`/`files_action`. |

### Step-level Variable Overrides

The `variables` field on any step maps additional `@placeholder@` strings to existing context variable names. This lets a generic command use a different `@alias@` name for a variable that was already set under a different name.

In the example below, the command uses `@inf_file@` as a placeholder, which is remapped to the built-in context variable `driver_inf` (whose value is e.g. `balloon.inf`):

```json
{
    "desc": "Install specific INF",
    "guest_run": "pnputil -i -a C:\\pkg\\@inf_file@",
    "variables": {
        "@inf_file@": "driver_inf"
    }
}
```

### Captured Output Variables

Use `capture_output` to store a step's output into a named variable and reference it in later steps:

```json
{
    "desc": "Get driver version",
    "guest_run": "(Get-Item C:\\Windows\\System32\\drivers\\@driver_module@.sys).VersionInfo.FileVersion",
    "capture_output": "driver_version"
},
{
    "desc": "Log driver version",
    "host_run": "echo 'Driver version: @driver_version@'"
}
```

---

## Workspace Output

The workspace is created at `<workspace_root>/functest/<engine_tag>/<timestamp>/`, where `<engine_tag>` is `<drivers>-<platform>` when drivers are specified, or `functest-<platform>` when no drivers are specified.

The following files are written by functest:

| File | Description |
|---|---|
| `functest_results.json` | Full structured results: total, passed, failed, per-test status, per-step status, durations, error messages |
| `<engine_tag>.log` | Full engine log (e.g. `Balloon-Win2025x64_gui.log` or `functest-Win2025x64_gui.log`) |
| `junit.xml` | JUnit-format results |
| `results.html` | HTML results report |
| `results.yaml` | YAML results report |
| `<test_name>_minidumps.zip` | Minidump archive collected from `%SystemRoot%\Minidump` after each test; only created if dumps exist |

The workspace also contains setup manager infrastructure files (`qemuhck.txt`, `pid`, `swtpm_*`, `uefi_*`, etc.).

The engine exits `0` if all tests passed, `1` if any test failed.
