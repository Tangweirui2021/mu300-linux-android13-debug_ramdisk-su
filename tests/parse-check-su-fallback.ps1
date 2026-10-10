# Syntax check for the su-fallback variants, shared helper and regression tests.
foreach ($f in @(
        (Join-Path $PSScriptRoot '..\install-su-fallback.ps1'),
        (Join-Path $PSScriptRoot '..\uninstall-su-fallback.ps1'),
        (Join-Path $PSScriptRoot '..\tools\su-fallback.ps1'),
        (Join-Path $PSScriptRoot 'su-fallback.Tests.ps1'))) {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) {
        Write-Host "$f : $($errors.Count) parse error(s)"
        $errors | ForEach-Object { Write-Host ("  line {0}: {1}" -f $_.Extent.StartLineNumber, $_.Message) }
        exit 1
    }
    Write-Host "$f : OK"
}
exit 0
