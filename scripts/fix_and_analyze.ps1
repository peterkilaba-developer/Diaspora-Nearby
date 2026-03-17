# =============================================================================
# Diaspora Nearby - Auto-Fix and Analyze Script
# 
# Runs dart fix, dart format, and dart analyze on lib/ to ensure zero issues.
# Usage:  .\scripts\fix_and_analyze.ps1
# =============================================================================

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent $PSScriptRoot

Push-Location $projectRoot

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Diaspora Nearby - Code Quality Check" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Auto-fix known lint issues
Write-Host "[1/3] Running dart fix --apply..." -ForegroundColor Yellow
$fixOutput = & dart fix --apply 2>&1
$fixExit = $LASTEXITCODE
if ($fixExit -ne 0) {
    Write-Host "  Warning: dart fix encountered issues (non-fatal)" -ForegroundColor DarkYellow
}
else {
    Write-Host "  Done: Auto-fixes applied" -ForegroundColor Green
}
Write-Host ""

# Step 2: Format all Dart files
Write-Host "[2/3] Running dart format lib/..." -ForegroundColor Yellow
$formatOutput = & dart format lib/ 2>&1
Write-Host "  Done: Files formatted" -ForegroundColor Green
Write-Host ""

# Step 3: Analyze for remaining issues
Write-Host "[3/3] Running dart analyze lib/..." -ForegroundColor Yellow
$analyzeOutput = & dart analyze lib/ 2>&1
$analyzeExitCode = $LASTEXITCODE

if ($analyzeExitCode -eq 0) {
    Write-Host "  Done: Zero issues found - lib/ is clean!" -ForegroundColor Green
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  ALL CHECKS PASSED" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
}
else {
    Write-Host ""
    Write-Host ($analyzeOutput -join "`n")
    Write-Host ""
    $errorCount = ($analyzeOutput | Select-String -Pattern " - " | Measure-Object).Count
    Write-Host "============================================" -ForegroundColor Red
    Write-Host "  $errorCount issue(s) need manual attention" -ForegroundColor Red
    Write-Host "============================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "  These issues could not be auto-fixed." -ForegroundColor DarkYellow
    Write-Host "  Common causes:" -ForegroundColor DarkYellow
    Write-Host "    - Deprecated API usage (needs manual migration)" -ForegroundColor DarkYellow
    Write-Host "    - Unused variables/imports after refactoring" -ForegroundColor DarkYellow
    Write-Host "    - Missing imports after moving classes" -ForegroundColor DarkYellow
}

Write-Host ""
Pop-Location
exit $analyzeExitCode
