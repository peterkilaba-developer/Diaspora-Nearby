#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
cd "$CI_PRIMARY_REPOSITORY_PATH"

# 1. Install Flutter (pinned to project version 3.44.8)
git clone https://github.com/flutter/flutter.git --depth 1 -b 3.44.8 "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

# 2. Disable experimental Swift Package Manager to use CocoaPods exclusively
flutter config --no-enable-swift-package-manager

# 3. Pre-download Flutter iOS artifacts
flutter precache --ios

# 4. Fetch Flutter dependencies
flutter pub get

# 5. Patch lucide_icons:
# (a) Patch icon_data.dart so LucideIconData does not extend final IconData
for icon_data_file in $(find "$HOME/.pub-cache" -name "icon_data.dart" 2>/dev/null); do
  cat << 'EOF' > "$icon_data_file"
class LucideIconData {
  final int codePoint;
  const LucideIconData(this.codePoint);
}
EOF
done

# (b) Patch lucide_icons.dart to construct IconData directly
for lucide_file in $(find "$HOME/.pub-cache" -name "lucide_icons.dart" 2>/dev/null); do
  sed -i.bak "s/const LucideIconData(\([^)]*\))/const IconData(\1, fontFamily: 'Lucide', fontPackage: 'lucide_icons')/g" "$lucide_file"
done

# 6. Generate iOS plugin symlinks and CocoaPods configuration for production scheme
flutter build ios --config-only --flavor production -t lib/main_production.dart --release

# 7. Ensure FunctionsStreamHandler.swift in cloud_functions is patched cleanly
for fn_file in $(find "$HOME/.pub-cache" "ios/.symlinks" -name "FunctionsStreamHandler.swift" 2>/dev/null); do
  python3 -c "
import sys, re
p = sys.argv[1]
with open(p, 'r') as f:
    c = f.read()
if 'var function: Callable<AnyEncodable, StreamResponse' in c:
    repl = '''await MainActor.run {\\n      events(\\n        FlutterError(\\n          code: \"unsupported\",\\n          message: \"Streaming callable functions require Firebase 12+ SDK\",\\n          details: nil\\n        )\\n      )\\n    }\\n  }\\n}'''
    c = re.sub(r'// Stream handling for iOS 15\+.*', repl, c, flags=re.DOTALL)
    with open(p, 'w') as f:
        f.write(c)
" "$fn_file"
done

exit 0
