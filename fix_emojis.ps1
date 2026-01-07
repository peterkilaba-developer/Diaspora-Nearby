$filePath = "C:\Projects\DiasporaNearby\lib\features\chat\screens\chat_screen.dart"
$content = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8)

# 1. Fix reaction menu using structural regex
$pattern = "children: \['.*?''\].map\(\(emoji\) \{"
$replacement = "children: ['❤️', '😂', '👍', '👎', '😮', '😢', '🙏', '🔥'].map((emoji) {"
$content = [regex]::Replace($content, $pattern, $replacement)

# 2. Fix debugPrint lines with placeholders or simpler regex
# We can find lines containing debugPrint and some specific Mojibake markers
# For simplicity, I'll just replace the most common one I saw: ðŸ  
$content = $content.Replace("ðŸ  ", "📩")
$content = $content.Replace("ðŸ“©", "📩")
$content = $content.Replace("ðŸ“‹", "📋")
$content = $content.Replace("ðŸ—‘", "🗑")
$content = $content.Replace("ðŸ“ ", "📍")
$content = $content.Replace("ðŸ’¾", "💾")
$content = $content.Replace("ðŸ‘ ï¸ ", "👁️")
$content = $content.Replace("â ¤ï¸ ", "❤️")

[System.IO.File]::WriteAllText($filePath, $content, [System.Text.Encoding]::UTF8)
Write-Host "Replacement complete."
