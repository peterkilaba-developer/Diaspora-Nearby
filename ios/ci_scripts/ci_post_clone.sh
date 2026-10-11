#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
cd "$CI_PRIMARY_REPOSITORY_PATH"

# 1. Install Flutter (pinned to project version 3.44.8)
git clone https://github.com/flutter/flutter.git --depth 1 -b 3.44.8 "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

# 2. Pre-download Flutter iOS artifacts
flutter precache --ios

# 3. Fetch Flutter dependencies
flutter pub get

# 4. Patch lucide_icons (fixes 'IconData cannot be extended' in modern Flutter)
for icon_file in $(find "$HOME/.pub-cache" -name "icon_data.dart" 2>/dev/null | grep "lucide_icons"); do
  cat << 'EOF' > "$icon_file"
import 'package:flutter/widgets.dart';
typedef LucideIconData = IconData;
EOF
done

# 5. Install CocoaPods on Xcode Cloud runner
HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods

# 6. Install CocoaPods dependencies
cd ios && pod install

exit 0
