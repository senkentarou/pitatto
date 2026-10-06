#!/bin/bash
# Builds build/Pitatto.app from the SPM executable.
#
# Xcode is not involved: what is needed is a signed, launchable .app, and
# nothing else a project file would provide.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
APP="build/Pitatto.app"
# TCC identifies an app by its code signature. An ad-hoc signature ("-") is
# different on every build, so macOS would treat each rebuild as a new app and
# drop the Accessibility grant — every rebuild would need the permission
# again. A fixed self-signed certificate keeps the grant across rebuilds; make
# one once in Keychain Access (Certificate Assistant › Create a Certificate,
# type "Code Signing") named below.
#
# A Developer ID build passes
# `CODESIGN_IDENTITY="Developer ID Application: …" ./scripts/bundle.sh`. The
# identity is not hard-coded here because it names a specific Apple developer
# account and this repository is public.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-Pitatto Dev}"

# -warnings-as-errors here as well as in `make build`: the gate builds debug,
# but this is the configuration that ships. Release uses whole-module
# optimization, so it can diagnose what per-file debug compilation cannot.
swift build -c "$CONFIGURATION" -Xswiftc -warnings-as-errors --product Pitatto
BINARY="$(swift build -c "$CONFIGURATION" --product Pitatto --show-bin-path)/Pitatto"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Pitatto"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Pitatto.icns "$APP/Contents/Resources/Pitatto.icns"
# The licence travels with the binary, not just with the repository. GPL-3.0 §4
# asks for a copy of the licence alongside every copy of the program, and a
# .zip handed to someone else is a copy that carries no repository.
cp LICENSE "$APP/Contents/Resources/LICENSE"

# A secure timestamp is a round trip to Apple's timestamp server: a rebuild does
# not need one and cannot get one offline, but notarization refuses a signature
# without it. A Developer ID build overrides this with --timestamp.
CODESIGN_TIMESTAMP="${CODESIGN_TIMESTAMP:---timestamp=none}"

# Hardened runtime is what a Developer ID build is expected to carry, and
# turning it on here means the signing flags are settled once.
codesign --force --options runtime "$CODESIGN_TIMESTAMP" \
	--sign "$CODESIGN_IDENTITY" "$APP"
codesign --verify --verbose=2 "$APP"

echo "built $APP"
