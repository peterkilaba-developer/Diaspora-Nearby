
import json
import re

try:
    with open('clean_list.json', 'r', encoding='utf-8') as f:
        content = f.read()
except:
    with open('clean_list.json', 'r', encoding='utf-16') as f:
        content = f.read()

# The file might contain garbage headers/footers from the shell output.
# We look for the JSON array start and end.
start = content.find('[')
end = content.rfind(']')

if start != -1 and end != -1:
    clean_json = content[start:end+1]
    try:
        data = json.loads(clean_json)
        for func in data:
             print(f"FUNCTION: {func.get('id')}")
    except json.JSONDecodeError as e:
        print(f"JSON Error: {e}")
        # Fallback regex
        ids = re.findall(r'"id":\s*"([^"]+)"', content)
        for i in ids:
            print(f"FUNCTION_REGEX: {i}")

else:
    print("Could not find JSON array brackets.")
