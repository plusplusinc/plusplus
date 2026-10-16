# Tools Xcode does not ship. `brew bundle` installs them; CI runs the same file.
brew "swiftformat"   # formatting (.swiftformat)
brew "swiftlint"     # lint (.swiftlint.yml)
brew "xcbeautify"    # readable xcodebuild output in scripts/
# App Store Connect and Xcode Cloud from the terminal (docs/xcode-cloud.md)
brew "asc" unless ENV["CI"]
brew "ffmpeg" unless ENV["CI"] # frames out of a simulator recording, to check motion (/run)
