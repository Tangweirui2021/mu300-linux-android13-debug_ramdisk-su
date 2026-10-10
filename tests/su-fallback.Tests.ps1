# Regression tests: extracted functions, mocked adb and local hash fixtures; no device or network access.
# powershell -NoProfile -ExecutionPolicy Bypass -File tests\su-fallback.Tests.ps1
$ErrorActionPreference = 'Stop'
$Top = Split-Path -Parent $PSScriptRoot
$script:passed = 0
function Check($name, $condition) {
    if (-not $condition) { throw "FAIL: $name" }
    $script:passed++
}
function ImportFunctions($path, $names) {
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$parseErrors)
    Check "parse $path" ($parseErrors.Count -eq 0)
    $defs = $ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $names -contains $n.Name
    }, $true)
    Check "functions present in $path" ($defs.Count -eq $names.Count)
    foreach ($d in $defs) { . ([scriptblock]::Create('function script:' + $d.Name + $d.Extent.Text.Substring(('function ' + $d.Name).Length))) }
}
ImportFunctions (Join-Path $Top 'tools\su-fallback.ps1') @('FindDeviceSu', 'WaitAndroidRoot')

# Success and failures can be delayed by the mocked sleep. No real adb command can escape this stub.
function adb {
    $request = $args -join ' '
    $global:LASTEXITCODE = 0
    $script:calls.Add($request)
    if ($request -eq 'shell getprop sys.boot_completed') {
        if ($script:tick -lt $script:bootAfter) { return '0' }
        return "1`r"
    }
    if ($request -match "^shell (\S+) -c 'id -u'$") {
        if ($script:tick -lt $script:bootAfter) { throw 'root probed before boot completion' }
        if ($Matches[1] -eq $script:workingSu -and $script:tick -ge $script:rootAfter) {
            $global:LASTEXITCODE = $script:rootStatus
            return $script:rootOutput
        }
        $global:LASTEXITCODE = 1
        return 'su: inaccessible or not found'
    }
    if ($request -eq "shell $script:workingSu -c 'printf hello'") { return "hello`r" }
    throw "unexpected adb operation: $request"
}
function Start-Sleep { param($Seconds) $script:tick++ }
function ResetMock($path = '/debug_ramdisk/su', $boot = 0, $root = 0, $output = "0`r", $status = 0) {
    $script:workingSu = $path; $script:bootAfter = $boot; $script:rootAfter = $root
    $script:rootOutput = $output; $script:rootStatus = $status; $script:tick = 0
    $script:calls = New-Object 'System.Collections.Generic.List[string]'
    $script:Su = '/stale/su'
    $env:MU300_SU = '/stale/su'
}

foreach ($variant in 'install-su-fallback.ps1', 'uninstall-su-fallback.ps1') {
    ImportFunctions (Join-Path $Top $variant) @('Quiet', 'SuDo')
    foreach ($candidate in 'su', '/debug_ramdisk/su', '/sbin/su', '/system/xbin/su', '/system/bin/su') {
        ResetMock $candidate
        Check "$variant selects $candidate" (WaitAndroidRoot -Attempts 3 -DelaySeconds 0 -Message '')
        Check "$variant remembers $candidate" ($script:Su -ceq $candidate)
        Check "$variant exports root path to child processes" ($env:MU300_SU -ceq $candidate)
        Check "$variant forwards root command" ((SuDo 'printf hello') -ceq 'hello')
        if ($candidate -eq 'su') { Check 'PATH su avoids extra probes' ($script:calls.Count -eq 3) }
    }
    ResetMock -boot 2 -root 3
    Check "$variant retries late boot and late root" (WaitAndroidRoot -Attempts 5 -DelaySeconds 0 -Message '')
    Check 'root became available on fourth round' ($script:tick -eq 3)
    Check 'fallback was retried' (@($script:calls | Where-Object { $_ -eq "shell /debug_ramdisk/su -c 'id -u'" }).Count -eq 2)
    foreach ($badOutput in '1000', 'ok', 'uid=0(root)', "0`n0") {
        ResetMock -output $badOutput
        Check "reject non-root or noisy output [$badOutput]" (-not (WaitAndroidRoot -Attempts 2 -DelaySeconds 0 -Message ''))
        Check 'failed probes clear stale root path' ($null -eq $script:Su)
        Check 'failed probes clear child root path' ([string]::IsNullOrEmpty($env:MU300_SU))
    }
    ResetMock -status 1
    Check 'uid 0 with failed adb status is refused' (-not (WaitAndroidRoot -Attempts 2 -DelaySeconds 0 -Message ''))
    ResetMock -boot 99
    Check 'unfinished boot times out' (-not (WaitAndroidRoot -Attempts 3 -DelaySeconds 0 -Message ''))
    Check 'unfinished boot never probes root' (@($script:calls | Where-Object { $_ -match 'id -u' }).Count -eq 0)
    Check 'unfinished boot clears child root path' ([string]::IsNullOrEmpty($env:MU300_SU))
    Check 'no sleep after final attempt' ($script:tick -eq 2)
    ResetMock -root 99
    Check 'missing root times out' (-not (WaitAndroidRoot -Attempts 3 -DelaySeconds 0 -Message ''))
    Check 'timeout clears stale root path' ($null -eq $script:Su)
    Check 'timeout clears child root path' ([string]::IsNullOrEmpty($env:MU300_SU))
    $source = [IO.File]::ReadAllText((Join-Path $Top $variant))
    Check 'variant loads shared helper' ($source.Contains(". (Join-Path `$Top 'tools\su-fallback.ps1')"))
    Check 'variant uses readiness gate' ($source.Contains('if (-not (WaitAndroidRoot '))
    Check 'old marker probe removed' (-not $source.Contains("-c 'echo ok'"))
}
ImportFunctions (Join-Path $Top 'install-su-fallback.ps1') @('SelfUpdate')
Check 'local source self-update disabled by default' (-not (SelfUpdate))
$install = [IO.File]::ReadAllText((Join-Path $Top 'install-su-fallback.ps1'))
Check 'no upstream source updater remains' ($install -notmatch 'commits/main|codeload.github.com|if \(SelfUpdate\)')
ImportFunctions (Join-Path $Top 'install-su-fallback.ps1') @('FileSha256')
# Reproduce the unavailable cmdlet without changing the host's installed PowerShell modules.
function Get-FileHash { throw 'Get-FileHash is unavailable in this regression test' }
$hashAst = [System.Management.Automation.Language.Parser]::ParseInput($install, [ref]$null, [ref]$null)
$oldHashCalls = $hashAst.FindAll({ param($n)
    $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Get-FileHash'
}, $true)
Check 'installer has no dependency on the unavailable hash cmdlet' ($oldHashCalls.Count -eq 0)
$hashDir = Join-Path $Top ('work\hash-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $hashDir -Force | Out-Null
$hashFile = Join-Path $hashDir ('hash [1] ' + [char]0x4E2D + '.bin')
try {
    [IO.File]::WriteAllBytes($hashFile, [byte[]]@())
    Check 'SHA256 empty file' ((FileSha256 $hashFile) -ceq 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
    [IO.File]::WriteAllBytes($hashFile, [Text.Encoding]::ASCII.GetBytes('abc'))
    Check 'SHA256 known text' ((FileSha256 $hashFile) -ceq 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
    [IO.File]::WriteAllBytes($hashFile, [byte[]](0..255))
    $binaryHash = '40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880'
    Check 'SHA256 binary file' ((FileSha256 $hashFile) -ceq $binaryHash)
    Push-Location -LiteralPath $hashDir
    try {
        Check 'literal relative path with spaces, brackets and Unicode' ((FileSha256 ([IO.Path]::GetFileName($hashFile))) -ceq $binaryHash)
    } finally { Pop-Location }
    $exclusive = [IO.File]::Open($hashFile, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { Check 'hashing releases the file handle' $exclusive.CanWrite } finally { $exclusive.Dispose() }
    $missingFailed = $false
    try { FileSha256 (Join-Path $hashDir 'missing.bin') | Out-Null } catch { $missingFailed = $true }
    Check 'missing file fails instead of silently accepting it' $missingFailed
} finally {
    # Delete only this test's literal file and empty directory; never recurse over a computed path.
    [IO.File]::Delete($hashFile)
    [IO.Directory]::Delete($hashDir)
}
Write-Host "$script:passed checks passed (mocked adb; no device writes)."
