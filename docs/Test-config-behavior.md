# Test Configuration Behavior

Test configuration provides the ability to configure guest/host before/after specific test runs.

## Configuration Options

Test configuration has the following options:

- **tests** - List of tests where config should be applied (string parsed as a regex)
- **secure** - Optional boolean to run guest in Secure Boot
- **parameters** - Array of HLK test parameter name/value pairs
- **pre_test_commands** - Array of commands to run before test execution
- **post_test_commands** - Array of commands to run after test execution

### Pre and Post Test Commands Options

- **desc** - String description of the command
- **host_run** - Optional string command to run on the host
- **guest_run** - Optional string command to run on each client VM
- **guest_reboot** - This option is only applicable to post-start commands and is ignored for pre and post test commands. It controls whether the guest VM should be rebooted after certain operations, but has no effect in this context.
- **files_action** - Array of file operations to perform

### File Action Configuration Options

- **remote_path** - Path to file or directory on client VM
- **local_path** - Path to file or directory on the host running AutoHCK
- **direction** - Direction of the file action (default: `remote-to-local`)
- **move** - Boolean flag to move file/directory (default: `false`, means copy)
- **allow_missing** - Boolean flag to allow missing file/directory (default: `false`)

## Test Configuration Execution Order

Test configuration is executed in the following order:

1. **Pre test commands**
   1. Guest command is executed on each client VM
   2. Host command is executed on the host
   3. Files action is executed
2. **Test execution**
3. **Post test commands**
   1. Guest command is executed on each client VM
   2. Host command is executed on the host
   3. Files action is executed

## File Action Behavior

- If `allow_missing` flag is set to `false` and source file/directory is missing, an error is raised
- If `move` flag is set to `true`, file/directory is moved according to the direction
- If `move` flag is set to `false`, file/directory is copied according to the direction

- If `remote_path` is empty, files will be copied to C:\ drive
- If `local_path` is empty, files will be copied to the current workspace

### Path Replacements

Local path can use the following replacements:

- `@workspace@` - Path to current workspace
- `@safe_test_name@` - Safe name of current test
- `@client_name@` - Client name
