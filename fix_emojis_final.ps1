$filePath = "C:\Projects\DiasporaNearby\lib\features\chat\screens\chat_screen.dart"
$content = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8)

$emojiHeart = [char]0x2764 + [char]0xFE0F
$emojiLaugh = [char]::ConvertFromUtf32(0x1F602)
$emojiThumbUp = [char]::ConvertFromUtf32(0x1F44D)
$emojiThumbDown = [char]::ConvertFromUtf32(0x1F44E)
$emojiO = [char]::ConvertFromUtf32(0x1F62E)
$emojiCry = [char]::ConvertFromUtf32(0x1F622)
$emojiPray = [char]::ConvertFromUtf32(0x1F64F)
$emojiFire = [char]::ConvertFromUtf32(0x1F525)

$emojiList = "'$emojiHeart', '$emojiLaugh', '$emojiThumbUp', '$emojiThumbDown', '$emojiO', '$emojiCry', '$emojiPray', '$emojiFire'"

# structural regex to avoid matching literal Mojibake
# Correcting the pattern to match single quotes correctly
$pattern = "children: \['.*?'].map\(\(emoji\) \{"
$replacement = "children: [$emojiList].map((emoji) {"
$content = [regex]::Replace($content, $pattern, $replacement)

[System.IO.File]::WriteAllText($filePath, $content, [System.Text.Encoding]::UTF8)
Write-Host "Success"
