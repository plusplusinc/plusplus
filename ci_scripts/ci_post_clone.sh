#!/bin/bash
# Xcode Cloud runs this right after cloning, before any build action.
#
# Installs the tools Xcode does not ship, then fails the workflow early on any formatting,
# lint, or spelling finding so a red build says "lint" and not something cryptic from deep
# inside xcodebuild. Tests run through the scheme's test action, configured in the workflow.
set -euo pipefail

cd "$CI_PRIMARY_REPOSITORY_PATH"

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
brew bundle

scripts/lint.sh
