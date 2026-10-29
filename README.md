# AutoHCK

[![GitHub Actions](https://github.com/HCK-CI/AutoHCK/actions/workflows/check.yml/badge.svg)](https://github.com/HCK-CI/AutoHCK/actions)

AutoHCK is a tool for automating HCK/HLK test suites used for WHQL certification, doing all the boilerplate steps in the process leaving you with simply choosing which driver you want to test on what OS.

See all details in [wiki](https://github.com/HCK-CI/AutoHCK/blob/master/docs/Home.md)

## Exit codes

`bin/auto_hck` exits with one of the following codes, so callers can tell a
test verdict apart from a framework failure without parsing the result
artifacts (`results.yaml`, `junit.xml`, `functest_results.json`):

| Code | Meaning |
| ---- | ------- |
| `0`  | Run completed and passed, or nothing was run (query mode, diff checker skip). |
| `1`  | Run aborted or canceled: uncaught exception (framework error) or interrupt. Generally retry-worthy. |
| `2`  | Run completed but one or more tests failed. Final verdict, not retry-worthy. |

## Authors

* **Lior Haim** - *Development* - [Daynix Computing LTD](https://github.com/Daynix)
* **Bishara AbuHattoum** - *Development* - [Daynix Computing LTD](https://github.com/Daynix)
* **Basil Salman** - *Development* - [Daynix Computing LTD](https://github.com/Daynix)
* **Kostiantyn Kostiuk** - *Development* - [Daynix Computing LTD](https://github.com/Daynix)
