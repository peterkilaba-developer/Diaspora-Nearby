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

exit 0
