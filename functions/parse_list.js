
const fs = require('fs');

try {
    const content = fs.readFileSync('clean_list.json', 'utf8');

    // Attempt to find JSON array
    const start = content.indexOf('[');
    const end = content.lastIndexOf(']');

    if (start !== -1 && end !== -1) {
        const jsonStr = content.substring(start, end + 1);
        try {
            const data = JSON.parse(jsonStr);
            data.forEach(fn => {
                console.log(`FUNCTION: ${fn.id}`);
            });
        } catch (e) {
            console.log("JSON Parse Error, trying regex");
            const regex = /"id":\s*"([^"]+)"/g;
            let match;
            while ((match = regex.exec(content)) !== null) {
                console.log(`FUNCTION_REGEX: ${match[1]}`);
            }
        }
    } else {
        console.log("No JSON brackets found. Dump:");
        console.log(content.substring(0, 500));
    }

} catch (e) {
    console.error(e);
}
