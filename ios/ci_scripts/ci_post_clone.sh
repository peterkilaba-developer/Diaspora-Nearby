#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
cd "$CI_PRIMARY_REPOSITORY_PATH"

# 1. Install Flutter using git (stable channel)
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

# 2. Pre-download Flutter iOS artifacts
flutter precache --ios

# 3. Fetch Flutter dependencies
flutter pub get

# 4. Install CocoaPods on Xcode Cloud runner
HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods

# 5. Install CocoaPods dependencies
cd ios && pod install

exit 0
