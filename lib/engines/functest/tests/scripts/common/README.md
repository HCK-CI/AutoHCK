# Common functest helpers (guest scripts)

Upload the scripts you need via the test case `files_action` step, for example:

```
local_path:  lib/engines/functest/tests/scripts/common/Invoke-InteractiveSession.ps1
remote_path: C:\AutoHCK\common\Invoke-InteractiveSession.ps1
```

Typical GUI flow:

```
Session 0 launcher -> Invoke-InteractiveSession.ps1 (-TaskName unique per test)
                   -> worker.ps1 on interactive desktop
                   -> Invoke-AutoIt.ps1 (-Au3Path ..., optional -WaitForFile)
```

Requires suite or case `extra_software: ["autoit"]` when using Invoke-AutoIt.ps1.
