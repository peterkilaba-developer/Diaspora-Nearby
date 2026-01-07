$filePath = "C:\Projects\DiasporaNearby\lib\features\chat\screens\chat_screen.dart"
$content = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8)

# Line 310: debugPrint('... Chat created:
$emojiCheck = [char]::ConvertFromUtf32(0x2705)
$content = [regex]::Replace($content, "debugPrint\('.*? Chat created:", "debugPrint('$emojiCheck Chat created:")

[System.IO.File]::WriteAllText($filePath, $content, [System.Text.Encoding]::UTF8)
Write-Host "Success"
