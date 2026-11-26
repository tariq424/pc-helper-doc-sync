# PUBLIC REFERENCE COPY (sanitised): the live queue Doc ID is replaced by
# <YOUR_QUEUE_DOC_ID>. Everything else is the exact v2 script running on the PC.
# doc-sync.ps1 - PC Helper Doc Sync (v2, Koda 2026-10-31)
# Tariq's rule (2026-10-31): scripts enter the git repo ONLY after they
# have run successfully ("validated and functional"). Results always
# come back regardless.
#
# How v2 enforces it: a materialised job folder is added to the repo's
# LOCAL exclude list (.git/info/exclude), so no git add -A (the helper's
# result push, heartbeats) can sweep the script in early. When the job's
# result log appears and it is NOT a BLOCKED / TIMEOUT result, the sync
# removes the exclude line and archives the script with its own commit:
# "archive proven job <id>". Blocked / timed-out scripts are never
# archived - they live only in the Doc and on this PC.
# The Doc remains the permanent archive of every script Koda sends.


$ErrorActionPreference = 'Continue'
$DocExportUrl = 'https://docs.google.com/document/d/<YOUR_QUEUE_DOC_ID>/export?format=txt'
$WorkDir      = 'F:\code\pc-helper'
$RepoDir      = Join-Path $WorkDir 'jobs-repo'
$LedgerFile   = Join-Path $WorkDir 'doc-sync-done.txt'
$ArchiveFile  = Join-Path $WorkDir 'doc-sync-archived.txt'
$LogFile      = Join-Path $WorkDir 'doc-sync.log'
$ExcludeFile  = Join-Path $RepoDir '.git\info\exclude'
$PollSeconds  = 45


if (-not (Test-Path $LedgerFile))  { New-Item -ItemType File -Path $LedgerFile  | Out-Null }
if (-not (Test-Path $ArchiveFile)) { New-Item -ItemType File -Path $ArchiveFile | Out-Null }


function SLog([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $LogFile -Value $line
}


function Add-Exclude([string]$id) {
    $line = "jobs/$id/"
    $cur = @()
    if (Test-Path $ExcludeFile) { $cur = @(Get-Content $ExcludeFile) }
    if ($cur -notcontains $line) { Add-Content -Path $ExcludeFile -Value $line }
}


function Remove-Exclude([string]$id) {
    $line = "jobs/$id/"
    if (Test-Path $ExcludeFile) {
        $kept = @(Get-Content $ExcludeFile | Where-Object { $_ -ne $line })
        Set-Content -Path $ExcludeFile -Value $kept
    }
}


SLog 'Doc sync v2 started. Scripts archive only after a successful run.'


while ($true) {
    try {
        # --- 1) materialise new jobs from the Doc (excluded from git) ---
        $txt = (Invoke-WebRequest -UseBasicParsing -Uri $DocExportUrl -TimeoutSec 30).Content
        if ($txt) {
            $done = @(Get-Content $LedgerFile | Where-Object { $_.Trim() })
            # marker strings built by concatenation so this file's own
            # source never contains the literal markers (it is itself
            # delivered inside a JOB block)
            $beginM = '-----BEGIN ' + 'SCRIPT-----'
            $endM   = '-----END ' + 'SCRIPT-----'
            $pattern = '(?sm)=== JOB (?<id>[A-Za-z0-9\-_]+) ===.*?' + [regex]::Escape($beginM) + '\r?\n(?<body>.*?)' + [regex]::Escape($endM)
            $matches = [regex]::Matches($txt, $pattern)
            foreach ($m in $matches) {
                $id = $m.Groups['id'].Value.Trim()
                if ($done -contains $id) { continue }
                $jobDir = Join-Path $RepoDir ("jobs\{0}" -f $id)
                if (-not (Test-Path $jobDir)) { New-Item -ItemType Directory -Path $jobDir -Force | Out-Null }
                Set-Content -Path (Join-Path $jobDir 'run.ps1') -Value $m.Groups['body'].Value -Encoding UTF8
                Add-Exclude $id
                Add-Content -Path $LedgerFile -Value $id
                SLog ("materialised JOB {0} from the Doc (held out of git until it runs)" -f $id)
            }
        }


        # --- 2) archive scripts whose jobs ran clean; never archive failures ---
        $materialised = @(Get-Content $LedgerFile  | Where-Object { $_.Trim() })
        $archived     = @(Get-Content $ArchiveFile | Where-Object { $_.Trim() })
        foreach ($id in $materialised) {
            if ($archived -contains $id) { continue }
            $resultLog = Join-Path $RepoDir ("results\{0}.log" -f $id)
            if (-not (Test-Path $resultLog)) { continue }
            $logText = Get-Content $resultLog -Raw
            if ($logText -match 'BLOCKED by helper guard' -or $logText -match 'TIMEOUT after') {
                Add-Content -Path $ArchiveFile -Value $id
                SLog ("JOB {0}: result was BLOCKED/TIMEOUT - script NOT archived" -f $id)
                continue
            }
            Remove-Exclude $id
            & git -C $RepoDir add ("jobs/{0}" -f $id) 2>&1 | Out-Null
            & git -C $RepoDir commit -m ("archive proven job {0}" -f $id) 2>&1 | Out-Null
            & git -C $RepoDir push 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Add-Content -Path $ArchiveFile -Value $id
                SLog ("JOB {0}: ran clean - script archived to the repo" -f $id)
            } else {
                Add-Exclude $id
                SLog ("JOB {0}: archive push failed - will retry next loop" -f $id)
            }
        }
    } catch {
        SLog ("loop error (keeps running): {0}" -f $_.Exception.Message)
    }
    Start-Sleep -Seconds $PollSeconds
}