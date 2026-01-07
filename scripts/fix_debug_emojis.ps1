$filePath = "C:\Projects\DiasporaNearby\lib\features\chat\screens\chat_screen.dart"
$content = [System.IO.File]::ReadAllText($filePath, [System.Text.Encoding]::UTF8)

# Construct emojis using Unicode codepoints
$emojiMail = [char]::ConvertFromUtf32(0x1F4E9)
$emojiClipboard = [char]::ConvertFromUtf32(0x1F4CB)
$emojiTrash = [char]::ConvertFromUtf32(0x1F5D1)
$emojiPin = [char]::ConvertFromUtf32(0x1F4CD)
$emojiFloppy = [char]::ConvertFromUtf32(0x1F4BE)
$emojiEye = [char]::ConvertFromUtf32(0x1F441) + [char]0xFE0F

# Using regex to find the specific corrupted strings I saw in the file
# Note: I'm matching specifically the strings from my view_file output to be safe.

# Pattern for 'ðŸ   ChatScreen INIT:'
$content = $content -replace "debugPrint\('.*? ChatScreen INIT:", "debugPrint('$emojiMail ChatScreen INIT:"
# Pattern for 'Restored scroll position:'
$content = $content -replace "debugPrint\('.*? Restored scroll position:", "debugPrint('$emojiPin Restored scroll position:"
# Pattern for 'Saved scroll position:'
$content = $content -replace "debugPrint\('.*? Saved scroll position:", "debugPrint('$emojiFloppy Saved scroll position:"
# Pattern for 'Marking .* visibility_changed' (if any)
$content = $content -replace "debugPrint\('.*? Marking .* messages as read", "debugPrint('$emojiEye Marking `$1 messages as read"

# Global replace for other known ones if they appear exactly like this
# ðŸ“© -> 📩
$content = $content -replace "ðŸ“©", $emojiMail
# ðŸ‹ -> 📋
$content = $content -replace "ðŸ“‹", $emojiClipboard

[System.IO.File]::WriteAllText($filePath, $content, [System.Text.Encoding]::UTF8)
Write-Host "Success"
