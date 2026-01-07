$filePath = "C:\Projects\DiasporaNearby\lib\features\chat\screens\chat_screen.dart"
$content = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8)

# Construct emojis using Unicode codepoints (100% ASCII script)
$emojiHeart = [char]0x2764 + [char]0xFE0F
$emojiLaugh = [char]::ConvertFromUtf32(0x1F602)
$emojiThumbUp = [char]::ConvertFromUtf32(0x1F44D)
$emojiThumbDown = [char]::ConvertFromUtf32(0x1F44E)
$emojiO = [char]::ConvertFromUtf32(0x1F62E)
$emojiCry = [char]::ConvertFromUtf32(0x1F622)
$emojiPray = [char]::ConvertFromUtf32(0x1F64F)
$emojiFire = [char]::ConvertFromUtf32(0x1F525)

$emojiList = "'$emojiHeart', '$emojiLaugh', '$emojiThumbUp', '$emojiThumbDown', '$emojiO', '$emojiCry', '$emojiPray', '$emojiFire'"

# Fix reaction menu using structural regex
$pattern = "children: \['.*?''\].map\(\(emoji\) \{"
$replacement = "children: [$emojiList].map((emoji) {"
$content = [regex]::Replace($content, $pattern, $replacement)

# Fix some debugPrint markers using ASCII sequences if possible
# Or just use the structural replacement for the most common ones
$content = $content -replace "debugPrint\('ðŸ   ChatScreen INIT:", "debugPrint('📩 ChatScreen INIT:"
$content = $content -replace "Restored scroll position:", "📍 Restored scroll position:"
$content = $content -replace "Saved scroll position:", "💾 Saved scroll position:"

[System.IO.File]::WriteAllText($filePath, $content, [System.Text.Encoding]::UTF8)
Write-Host "ASCII script replacement complete."
