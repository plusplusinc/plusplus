# Tools Xcode does not ship. `brew bundle` installs them; CI runs the same file. SwiftFormat and
# SwiftLint are not here: brew installs only the newest, so scripts/lint-tools.sh pins them.
brew "xcbeautify"    # readable xcodebuild output in scripts/
# App Store Connect and Xcode Cloud from the terminal (docs/xcode-cloud.md)
brew "asc" unless ENV["CI"]
brew "ffmpeg" unless ENV["CI"] # frames out of a simulator recording, to check motion (/run)
