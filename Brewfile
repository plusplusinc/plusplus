# Tools Xcode does not ship. `brew bundle` installs them; CI runs the same file.
brew "swiftformat"   # formatting (.swiftformat)
brew "swiftlint"     # lint (.swiftlint.yml)
brew "xcbeautify"    # readable xcodebuild output in scripts/
brew "asc" unless ENV["CI"]   # App Store Connect and Xcode Cloud from the terminal (docs/ci.md)
