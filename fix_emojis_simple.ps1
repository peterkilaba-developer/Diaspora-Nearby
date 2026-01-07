$filePath = "C:\Projects\DiasporaNearby\lib\features\chat\screens\chat_screen.dart"
$content = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8)

# Fix reaction menu using structural regex (no Mojibake in script)
$pattern = "children: \['.*?''\].map\(\(emoji\) \{"
$replacement = "children: ['❤️', '😂', '👍', '👎', '😮', '😢', '🙏', '🔥'].map((emoji) {"
$content = [regex]::Replace($content, $pattern, $replacement)

[System.IO.File]::WriteAllText($filePath, $content, [System.Text.Encoding]::UTF8)
Write-Host "Reaction menu fix applied."
