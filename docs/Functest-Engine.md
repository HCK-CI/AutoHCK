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
| `--driver-path <path>` | Host path to the driver package directory; required when drivers are configured |
| `--category <suite>` | Run a named test suite; `<suite>` is the suite name from `lib/engines/functest/tests/suites/<suite>.json` |
| `--testcase <names>` | Comma-separated list of test case names to run (e.g. `driver_sign_check,balloon/balloon_service`) |

Exactly one of `--category` or `--testcase` is required. All common options (`--verbose`, `--config`, `--id`, etc.) apply as documented in [Home](Home.md).

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

## Directory Layout

```
lib/engines/functest/
  functest.json                   Engine configuration
  tests/
    suites/                       Test suite definitions  (*.json)
    cases/                        Individual test cases   (*/*.json or *.json)
    scripts/                      PowerShell scripts used by guest_run_file steps
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
| `test_steps` | Yes | Ordered array of step objects; a failure aborts remaining steps |
| `cleanup` | No | Steps run after test completes (pass or fail); errors here do not change test status |

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

> Each step object must have **exactly one** step-type field (`guest_run`, `guest_run_file`, `guest_reboot`, `host_run`, `files_action`, `qmp_command`, `qmp_wait_event`, `barrier`). All other fields are optional modifiers.

### Common Step Fields

| Field | Description |
|---|---|
| `desc` | Human-readable description; logged and shown in results. |
| `timeout` | Step timeout in seconds; overrides the engine default of 300s. |
| `ignore_errors` | If `true`, a failure in this step does not abort the test. Useful for optional steps in `test_steps`. Default: `false`. |
| `variables` | Maps `@placeholder@` strings to existing context variable names for extra substitution within this step. |
| `capture_output` | Name of a variable to store the step's output in. For example, `"capture_output": "driver_version"` stores the output and makes it available as `@driver_version@` in subsequent steps. |
| `expected_output_contains` | The step fails if the command output does not contain this exact string. |
| `expected_output_matches` | The step fails if the command output does not match this regex pattern. |

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

Runs a command on the host machine running AutoHCK.

```json
{
    "desc": "Extract driver package on host",
    "host_run": "unzip /tmp/driver.zip -d /tmp/driver_extracted"
}
```

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

Blocks until a specific QEMU event is received from the client VM.

```json
{
    "desc": "Wait for balloon change event",
    "qmp_wait_event": {
        "event": "BALLOON_CHANGE",
        "timeout": 30
    }
}
```

#### `qmp_wait_event` Fields

| Field | Required | Description |
|---|---|---|
| `event` | Yes | QMP event name to wait for (e.g. `BALLOON_CHANGE`) |
| `timeout` | No | Maximum seconds to wait. Defaults to the engine `default_timeout`. |

---

### `barrier`

A named synchronization point. In the current single-VM implementation it only logs the barrier name and does nothing else. Reserved for future multi-VM support.

---

## Variable Substitution

Variables are substituted in `desc`, `guest_run`, `guest_run_file` (script body), `host_run`, `local_path`, and `remote_path` fields using the `@variable_name@` syntax.

### Built-in Variables

These are populated automatically from CLI arguments and driver configuration:

| Variable | Description |
|---|---|
| `@driver_path@` | Local path to the driver package directory (`--driver-path` CLI option) |
| `@driver_module@` | Driver module name derived from the INF filename (e.g. `balloon` from `balloon.inf`) |
| `@driver_inf@` | INF filename of the driver (e.g. `balloon.inf`) |
| `@driver_name@` | Full driver name as defined in the driver JSON configuration |

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
