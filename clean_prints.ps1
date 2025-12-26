$files = Get-ChildItem -Path lib -Filter *.dart -Recurse
foreach ($file in $files) {
    Write-Host "Cleaning $($file.FullName)"
    $content = Get-Content $file.FullName
    $newContent = $content -replace '^\s*debugPrint\(.*\);', '' -replace '^\s*print\(.*\);', ''
    $newContent | Set-Content $file.FullName
}
Á*