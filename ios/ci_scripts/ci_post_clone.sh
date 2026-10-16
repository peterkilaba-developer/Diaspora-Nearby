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

# 5.5 Ensure ios/Runner/GoogleService-Info.plist exists for Xcode archive
if [ -n "$GOOGLE_SERVICE_INFO_PLIST_BASE64" ]; then
  echo "$GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 --decode > "ios/Runner/GoogleService-Info.plist"
elif [ ! -f "ios/Runner/GoogleService-Info.plist" ]; then
  cat << 'EOF' > "ios/Runner/GoogleService-Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>API_KEY</key>
	<string>AIzaSyAnvuP6-HBvxxfSgNpiOR42lonoCTovhFw</string>
	<key>GCM_SENDER_ID</key>
	<string>512074182214</string>
	<key>PLIST_VERSION</key>
	<string>1</string>
	<key>BUNDLE_ID</key>
	<string>com.diasporanearby.diasporanearby</string>
	<key>PROJECT_ID</key>
	<string>diaspora-nearby-a3dac</string>
	<key>STORAGE_BUCKET</key>
	<string>diaspora-nearby-a3dac.firebasestorage.app</string>
	<key>IS_ADS_ENABLED</key>
	<false></false>
	<key>IS_ANALYTICS_ENABLED</key>
	<false></false>
	<key>IS_APPINVITE_ENABLED</key>
	<true></true>
	<key>IS_GCM_ENABLED</key>
	<true></true>
	<key>IS_SIGNIN_ENABLED</key>
	<true></true>
	<key>GOOGLE_APP_ID</key>
	<string>1:512074182214:ios:49c9f76543d41143b92447</string>
	<key>DATABASE_URL</key>
	<string>https://diaspora-nearby-a3dac-default-rtdb.firebaseio.com</string>
</dict>
</plist>
EOF
fi

# 6. Generate iOS plugin symlinks and CocoaPods configuration for production scheme
MAPS_KEY="${GOOGLE_MAPS_API_KEY:-AIzaSyAj0oAGYEX5osyDa_2Pn828clvv72UhEF8}"
flutter build ios --config-only --flavor production -t lib/main_production.dart --release --dart-define="GOOGLE_MAPS_API_KEY=$MAPS_KEY"

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
