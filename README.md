# Windows Dev Process Cleanup

A Codex skill for auditing and safely cleaning stale Windows development process trees and noisy UWP background-task pileups.

It focuses on conservative classification before termination, so active dev servers, editor language services, and ambiguous process trees are not killed by default.

## What it detects

### Development process trees

scripts/audit-dev-processes.ps1 audits Windows process trees involving:

- 
ode.exe
- 
pm.exe
- 
px.exe
- cmd.exe
- pwsh.exe

It classifies trees as:

- 
pm-outdated
- playwright-mcp
- dev-server
- ide-language-service
- generic

### UWP background task pileups

scripts/audit-uwp-backgroundtasks.ps1 audits app-associated ackgroundTaskHost.exe processes via 	asklist /apps, with focused handling for:

- Phone Link / Microsoft.YourPhone
- Dolby Access / DolbyLaboratories.DolbyAccess
- Microsoft Store / StorePurchaseApp / Microsoft To Do and other UWP groups

## Quick start

Audit dev process trees:

`powershell
pwsh -NoLogo -File scripts/audit-dev-processes.ps1 -Mode audit
`

Preview conservative cleanup:

`powershell
pwsh -NoLogo -File scripts/audit-dev-processes.ps1 -Mode cleanup -Profile safe -WhatIf
`

Run conservative cleanup for orphan 
pm outdated trees:

`powershell
pwsh -NoLogo -File scripts/audit-dev-processes.ps1 -Mode cleanup -Profile safe
`

Audit UWP/app background tasks:

`powershell
pwsh -NoLogo -File scripts/audit-uwp-backgroundtasks.ps1 -Mode audit
`

Disable Phone Link background access and terminate related app-associated processes:

`powershell
pwsh -NoLogo -File scripts/audit-uwp-backgroundtasks.ps1 -Mode cleanup -Profile phone-link-background -DisablePhoneLinkBackground
`

Terminate leaked Dolby Access ackgroundTaskHost.exe instances without disabling Dolby Access:

`powershell
pwsh -NoLogo -File scripts/audit-uwp-backgroundtasks.ps1 -Mode cleanup -Profile dolby-backgroundtask
`

## Cleanup profiles

### udit-dev-processes.ps1

- safe: terminate only clearly stale orphan 
pm-outdated trees.
- playwright-mcp: terminate Playwright MCP trees. Use only when browser automation workers are known to be stale.
- codex-playwright-safe: terminate stale Playwright MCP trees owned by Codex after the stale threshold.
- safe-plus-codex-playwright: combine orphan 
pm-outdated cleanup with stale Codex Playwright cleanup.
- workspace-dev-server: terminate only dev servers whose command lines match -WorkspacePath.

### udit-uwp-backgroundtasks.ps1

- phone-link-background: terminate Phone Link / Microsoft.YourPhone app-associated processes. Use -DisablePhoneLinkBackground to set HKCU background-access flags.
- dolby-backgroundtask: terminate only Dolby Access ackgroundTaskHost.exe instances. It does not disable or uninstall Dolby Access.

## Safety notes

- Always audit first.
- Prefer -WhatIf before non-trivial cleanup.
- Do not kill dev-server, ide-language-service, or generic trees without user confirmation.
- Do not disable Dolby Access by default because it may affect audio features.
- Phone Link background access should only be disabled when the user does not need background phone sync.

## Codex skill usage

The SKILL.md file describes when and how Codex should use the scripts.

## Requirements

- Windows
- PowerShell 7 recommended
- Built-in Windows commands: 	asklist, 	askkill
- CIM/WMI availability for process tree inspection

## License

MIT
