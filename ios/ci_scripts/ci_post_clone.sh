#!/bin/sh

# Fail this script if any subcommand fails.
set -e

# The default execution directory of this script is the ci_scripts directory.
cd $CI_PRIMARY_REPOSITORY_PATH

# Install Flutter using git (stable channel)
git clone https://github.com/flutter/flutter.git --depth 1 -b stable $HOME/flutter
export PATH="$PATH:$HOME/flutter/bin"

# Install Flutter dependencies for iOS
flutter precache --ios

# Install pub packages
flutter pub get

# Install CocoaPods dependencies
cd ios && pod install

exit 0
