# `make check` is the only gate. Run it before every commit.
SHELL := /bin/bash
APP   := build/Pitatto.app
# The copy that gets launched. /Applications rather than build/ for two reasons:
# SMAppService refuses to register a login item for an app outside a standard
# location, and the Accessibility grant is keyed on the code signature, so
# replacing the bundle in place keeps the permission across rebuilds instead of
# asking for it again.
DEST  := /Applications/Pitatto.app
# The version the release is named for, read from the one place that already
# has to be right: the bundle the updater compares against.
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
# A notarytool profile holds an Apple ID, not an app, so any profile for the
# signing team notarizes this bundle. Store one once with
# `xcrun notarytool store-credentials pitatto-notary`, or point at a profile
# that already exists with `make release NOTARY_PROFILE=<name>`.
NOTARY_PROFILE ?= pitatto-notary

.PHONY: build test lint format app install run stop check release clean

build:
	swift build -Xswiftc -warnings-as-errors

test:
	swift test

# swift-format's defaults (2-space indent, 100 columns) are the style here, so
# there is no .swift-format to keep in sync.
lint:
	swift format lint --strict --recursive --parallel Sources Tests
	@# PitattoCore holds decisions, not OS calls (Package.swift). SPM cannot
	@# enforce that: a system framework imports fine from any target, so the
	@# dependency graph only stops the other direction. An allowlist rather
	@# than a list of banned frameworks, because `@preconcurrency import` and
	@# `import class` are imports too. CoreGraphics is allowed: CGRect and
	@# CGFloat are value types Foundation re-exports anyway, so banning the
	@# import would buy nothing while making the frame arithmetic declare a
	@# parallel geometry type.
	@! grep -rhE '^[[:space:]]*(@[[:alnum:]_]+[[:space:]]+)*import[[:space:]]' Sources/PitattoCore \
		| grep -vqE '^import (Foundation|CoreGraphics)$$' \
		|| { echo 'PitattoCore may import only Foundation and CoreGraphics'; exit 1; }

format:
	swift format --in-place --recursive --parallel Sources Tests

app:
	./scripts/bundle.sh

# Quitting first is not optional: a second instance means a second set of hot
# key registrations, and the later one loses to the earlier — the app would look
# dead while an invisible copy of itself held the keys.
stop:
	@pkill -x Pitatto || true

install: app stop
	rm -rf $(DEST)
	cp -R $(APP) $(DEST)

run: install
	open $(DEST)

check: lint build test

# The zip that goes on a GitHub release. Notarized and stapled because the
# in-app updater hands it to someone else's Mac, where an un-notarized bundle
# is stopped by Gatekeeper. The asset name is what UpdateConfig.assetPrefix
# looks for, so it is not free to change.
#
# Needs CODESIGN_IDENTITY set to a Developer ID: the updater only accepts a
# bundle signed by UpdateConfig.teamID, and notarization refuses anything else.
#
# Then: gh release create v$(VERSION) build/Pitatto-$(VERSION).zip
# `$(MAKE) app` rather than a prerequisite: the release build needs a secure
# timestamp in its signature, and passing it through the environment is the
# only way to reach bundle.sh without changing what a plain `make app` does.
release:
	@[[ "$$CODESIGN_IDENTITY" == "Developer ID Application:"* ]] \
		|| { echo 'release needs CODESIGN_IDENTITY="Developer ID Application: …"'; exit 1; }
	CODESIGN_TIMESTAMP=--timestamp $(MAKE) app
	rm -f build/notarize.zip build/Pitatto-$(VERSION).zip
	ditto -c -k --keepParent $(APP) build/notarize.zip
	xcrun notarytool submit build/notarize.zip --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(APP)
	spctl -a -vv $(APP)
	ditto -c -k --keepParent $(APP) build/Pitatto-$(VERSION).zip
	@echo "built build/Pitatto-$(VERSION).zip"

clean:
	rm -rf .build build
