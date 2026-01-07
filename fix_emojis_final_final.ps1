$filePath = "C:\Projects\DiasporaNearby\lib\features\chat\screens\chat_screen.dart"
$content = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8)

# Construct emojis using Unicode codepoints
$emojiMail = [char]::ConvertFromUtf32(0x1F4E9)
$emojiPin = [char]::ConvertFromUtf32(0x1F4CD)
$emojiEye = [char]::ConvertFromUtf32(0x1F441) + [char]0xFE0F

# Use regex to find lines by code structure, not corrupted chars
# Line 289: debugPrint('... _sendMessage called with content:
$content = [regex]::Replace($content, "debugPrint\('.*? _sendMessage called", "debugPrint('$emojiMail _sendMessage called")

# Line 300: debugPrint('... Creating DM chat on first message...');
$content = [regex]::Replace($content, "debugPrint\('.*? Creating DM chat", "debugPrint('$emojiPin Creating DM chat")

# Fix the literal `$1` error at Line 270
$content = $content.Replace("👁️ Marking `$1 messages as read", "$emojiEye Marking visible messages as read")

[System.IO.File]::WriteAllText($filePath, $content, [System.Text.Encoding]::UTF8)
Write-Host "Success"
