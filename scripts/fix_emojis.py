import re

file_path = r'C:\Projects\DiasporaNearby\lib\features\chat\screens\chat_screen.dart'

with open(file_path, 'rb') as f:
    raw_content = f.read()

# I'll use bytes and regex on bytes to be absolutely sure
# The pattern for reaction bar is: children: [' followed by some bytes and ends with '].map((emoji) {'
# We can match it roughly with ASCII markers.

try:
    content = raw_content.decode('utf-8', errors='ignore')

    # Fix reaction menu
    # Pattern matches 'children: [' followed by anything until '].map((emoji) {'
    # Using re.DOTALL just in case
    reaction_pattern = r"children: \['.*?'\].map\(\(emoji\) \{"
    reaction_replacement = "children: ['❤️', '😂', '👍', '👎', '😮', '😢', '🙏', '🔥'].map((emoji) {"
    
    if re.search(reaction_pattern, content):
        content = re.sub(reaction_pattern, reaction_replacement, content)
        print("Fixed reaction menu.")
    else:
        print("Could not find reaction menu pattern.")

    # Fix debugPrint emojis
    replacements = {
        'ðŸ  ': '📩',
        'ðŸ“©': '📩',
        'ðŸ“‹': '📋',
        'ðŸ—‘': '🗑',
        'ðŸ“ ': '📍',
        'ðŸ’¾': '💾',
        'ðŸ‘ ï¸ ': '👁️',
        'â ¤ï¸ ': '❤️',
    }
    
    for old, new in replacements.items():
        if old in content:
            content = content.replace(old, new)
            print(f"Fixed {old} -> {new}")

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print("Write complete.")

except Exception as e:
    print(f"Error: {e}")
