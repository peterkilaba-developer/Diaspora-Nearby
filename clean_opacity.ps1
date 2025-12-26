$files = Get-ChildItem -Path lib -Filter *.dart -Recurse
foreach ($file in $files) {
    Write-Host "Cleaning $($file.FullName)"
    $content = Get-Content $file.FullName
    
    # Replace .withOpacity(0.X) with .withAlpha(Calculated)
    # This is a bit complex for a regex replace in one go, so we use a matches evaluator
    
    $newContent = [regex]::Replace($content, '\.withOpacity\(\s*([0-9.]+)\s*\)', {
        param($m)
        $opacity = [double]$m.Groups[1].Value
        $alpha = [int][Math]::Round($opacity * 255)
        return ".withAlpha($alpha)"
    })
    
    $newContent | Set-Content $file.FullName
}
*