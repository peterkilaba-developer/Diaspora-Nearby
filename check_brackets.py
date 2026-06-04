
filename = r"c:\Projects\DiasporaNearby\lib\features\chat\screens\group_info_screen.dart"

with open(filename, 'r', encoding='utf-8') as f:
    lines = f.readlines()

stack = []
for i, line in enumerate(lines):
    for j, char in enumerate(line):
        if char in '([{':
            stack.append((char, i+1, j+1))
        elif char in ')]}':
            if not stack:
                print(f"Error: Unmatched {char} at line {i+1}:{j+1}")
            else:
                last_char, last_line, last_col = stack.pop()
                expected = {'(': ')', '[': ']', '{': '}'}[last_char]
                if char != expected:
                    print(f"Error: Mismatch at line {i+1}:{j+1}. Found {char}, expected {expected} to match {last_char} from line {last_line}:{last_col}")

if stack:
    print("Error: Unclosed brackets:")
    for char, i, j in stack:
        print(f"  {char} at line {i}:{j}")
else:
    print("Brackets are balanced.")
