#!/bin/sh

# Xcode Cloud: trust Swift macros (SwiftfinMacros, StatefulMacros) and package plugins without
# interactive validation. CI builds already pass -skipMacroValidation to xcodebuild. See issue #2.

set -e

defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
