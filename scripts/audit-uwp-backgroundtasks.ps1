[CmdletBinding()]
param(
  [ValidateSet('audit', 'cleanup')]
  [string]$Mode = 'audit',

  [ValidateSet('none', 'phone-link-background', 'dolby-backgroundtask')]
  [string]$Profile = 'none',

  [switch]$DisablePhoneLinkBackground,

  [switch]$WhatIf,

  [switch]$AsJson
)

$ErrorActionPreference = 'Stop'

function Get-AppAssociatedTaskListRows {
  $raw = cmd /c "tasklist /apps" 2>$null
  foreach ($line in $raw) {
    if ($line -notmatch 'backgroundTaskHost\.exe|Microsoft\.YourPhone|PhoneExperienceHost|YourPhoneAppProxy|DolbyLaboratories\.DolbyAccess') {
      continue
    }

    $tokens = ($line.ToString() -split '\s+') | Where-Object { $_ -ne '' }
    $processId = $null
    foreach ($token in $tokens) {
      if ($token -match '^\d+$') {
        $processId = [int]$token
        break
      }
    }
    if (-not $processId) {
      continue
    }

    $app = 'unknown'
    if ($line -match '(Microsoft\.YourPhone_[^\s]+)') {
      $app = $matches[1]
    }
    elseif ($line -match '(DolbyLaboratories\.DolbyAccess_[^\s]+)') {
      $app = $matches[1]
    }
    elseif ($line -match '(Microsoft\.WindowsStore_[^\s]+)') {
      $app = $matches[1]
    }
    elseif ($line -match '(Microsoft\.StorePurchaseApp_[^\s]+)') {
      $app = $matches[1]
    }
    elseif ($line -match '(Microsoft\.Todos_[^\s]+)') {
      $app = $matches[1]
    }
    elseif ($line -match '([A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+_[^\s]+)') {
      $app = $matches[1]
    }

    $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
    [PSCustomObject]@{
      pid = $processId
      process_name = if ($proc) { $proc.ProcessName } else { ($tokens[0] -replace '\.exe.*$', '') }
      app = $app
      memory_mb = if ($proc) { [math]::Round($proc.WorkingSet64 / 1MB, 1) } else { 0 }
      started_at = if ($proc) { $proc.StartTime } else { $null }
      raw = $line.ToString()
    }
  }
}

function Get-UwpBackgroundTaskGroups {
  param([object[]]$Rows)

  $Rows |
    Group-Object app |
    ForEach-Object {
      $totalMb = ($_.Group | Measure-Object memory_mb -Sum).Sum
      $category = 'uwp-backgroundtask'
      $recommendation = 'review'
      $reason = 'UWP/app-associated background process group.'

      if ($_.Name -like 'Microsoft.YourPhone_*') {
        $category = 'phone-link-background'
        if ($_.Count -ge 10) {
          $recommendation = 'candidate-cleanup'
          $reason = 'Phone Link / Microsoft.YourPhone backgroundTaskHost pileup. It is normally safe to terminate when the user does not need background phone sync.'
        }
        else {
          $recommendation = 'keep-or-review'
          $reason = 'Phone Link process count is small.'
        }
      }
      elseif ($_.Name -like 'DolbyLaboratories.DolbyAccess_*') {
        $category = 'dolby-backgroundtask'
        if ($_.Count -ge 10) {
          $recommendation = 'candidate-cleanup-no-disable'
          $reason = '重点筛查: Dolby Access backgroundTaskHost pileup. Terminate leaked hosts only; do not disable Dolby if audio features are in use.'
        }
        else {
          $recommendation = 'keep'
          $reason = '重点筛查: Dolby Access process count is small.'
        }
      }

      [PSCustomObject]@{
        app = $_.Name
        category = $category
        count = $_.Count
        total_memory_mb = [math]::Round($totalMb, 1)
        oldest = ($_.Group | Sort-Object started_at | Select-Object -First 1).started_at
        newest = ($_.Group | Sort-Object started_at -Descending | Select-Object -First 1).started_at
        recommendation = $recommendation
        reason = $reason
        pids = @($_.Group.pid)
      }
    } |
    Sort-Object count -Descending
}

function Disable-PhoneLinkBackgroundAccess {
  $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications\Microsoft.YourPhone_8wekyb3d8bbwe'
  New-Item -Path $path -Force | Out-Null
  Set-ItemProperty -Path $path -Name 'Disabled' -Type DWord -Value 1
  Set-ItemProperty -Path $path -Name 'DisabledByUser' -Type DWord -Value 1
}

function Stop-Pids {
  param([int[]]$TargetPids)

  $unique = @($TargetPids | Sort-Object -Unique)
  foreach ($processId in $unique) {
    if (-not $WhatIf) {
      Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
  }

  [PSCustomObject]@{
    count = $unique.Count
    pids = $unique
    result = if ($WhatIf) { 'preview' } else { 'terminated' }
  }
}

$rows = @(Get-AppAssociatedTaskListRows)
$groups = @(Get-UwpBackgroundTaskGroups -Rows $rows)
$phoneLinkGroup = @($groups | Where-Object { $_.category -eq 'phone-link-background' })
$dolbyGroup = @($groups | Where-Object { $_.category -eq 'dolby-backgroundtask' })
$phoneLinkCount = if ($phoneLinkGroup.Count -gt 0) { @($phoneLinkGroup | ForEach-Object { $_.pids } | Where-Object { $_ -ne $null }).Count } else { 0 }
$dolbyBackgroundTaskCount = if ($dolbyGroup.Count -gt 0) { @($dolbyGroup | ForEach-Object { $_.pids } | Where-Object { $_ -ne $null }).Count } else { 0 }

$result = [PSCustomObject]@{
  mode = $Mode
  profile = $Profile
  what_if = [bool]$WhatIf
  summary = [PSCustomObject]@{
    total_app_associated_count = $rows.Count
    background_task_host_count = @($rows | Where-Object { $_.raw -match '^backgroundTaskHost\.exe' }).Count
    phone_link_count = $phoneLinkCount
    dolby_backgroundtask_count = $dolbyBackgroundTaskCount
  }
  groups = $groups
}

if ($Mode -eq 'cleanup') {
  $cleanupPids = @()
  if ($Profile -eq 'phone-link-background') {
    if ($DisablePhoneLinkBackground -and -not $WhatIf) {
      Disable-PhoneLinkBackgroundAccess
    }
    $cleanupPids = @($rows | Where-Object {
      $_.app -like 'Microsoft.YourPhone_*' -or
      $_.process_name -in @('PhoneExperienceHost', 'YourPhoneAppProxy', 'YourPhone')
    } | ForEach-Object { $_.pid })
  }
  elseif ($Profile -eq 'dolby-backgroundtask') {
    $cleanupPids = @($rows | Where-Object {
      $_.raw -match '^backgroundTaskHost\.exe' -and $_.app -like 'DolbyLaboratories.DolbyAccess_*'
    } | ForEach-Object { $_.pid })
  }

  $result | Add-Member -NotePropertyName cleanup -NotePropertyValue (Stop-Pids -Pids $cleanupPids)
}

if ($AsJson) {
  $result | ConvertTo-Json -Depth 6
  exit 0
}

$result.summary
''
'UWP/app-associated background groups:'
$result.groups | Select-Object app, category, count, total_memory_mb, recommendation, reason | Format-Table -AutoSize

if ($Mode -eq 'cleanup') {
  ''
  'Cleanup:'
  $result.cleanup | Format-List
}
