# Host-side helpers for the local su-fallback variants. Sourcing this file runs no device commands.
# Never accept an error containing a marker such as "ok": require both exit status 0 and uid 0.
function FindDeviceSu {
    $script:Su = $null
    $env:MU300_SU = $null
    foreach ($suCandidate_ in @('su', '/debug_ramdisk/su', '/sbin/su', '/system/xbin/su', '/system/bin/su')) {
        $suUid_ = ((Quiet { adb shell "$suCandidate_ -c 'id -u'" }) -join "`n") -replace "`r", ''
        if ($LASTEXITCODE -eq 0 -and $suUid_.Trim() -ceq '0') {
            $script:Su = $suCandidate_
            $env:MU300_SU = $suCandidate_ # Python/shell extractors run in child processes.
            return $true
        }
    }
    return $false
}

function WaitAndroidRoot([int]$Attempts = 60, [int]$DelaySeconds = 2,
                         [string]$Message = 'waiting for Android to finish starting and root access') {
    $script:Su = $null
    $env:MU300_SU = $null
    for ($suTry_ = 0; $suTry_ -lt $Attempts; $suTry_++) {
        # Boot readiness must not depend on a root path that has not yet been discovered.
        $suBoot_ = ((Quiet { adb shell getprop sys.boot_completed }) -join "`n") -replace "`r", ''
        if ($LASTEXITCODE -eq 0 -and $suBoot_.Trim() -ceq '1' -and (FindDeviceSu)) { return $true }
        if ($suTry_ -eq 0 -and $Message) { Write-Host "  $Message" }
        if ($suTry_ + 1 -lt $Attempts) { Start-Sleep -Seconds $DelaySeconds }
    }
    return $false
}
