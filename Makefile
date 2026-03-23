.PHONY: help try-local demo-vault docs-screenshots xcodeproj build-app notarize-app package-app package-dmg clean-app

help:
	@printf '%s\n' \
	"make try-local   Generate the Xcode project and open it for the easiest first run" \
	"make demo-vault  Generate a rich sample Obsidian vault under build/SampleVault" \
	"make docs-screenshots Generate polished product screenshots under docs/images" \
	"make xcodeproj   Generate Obviewer.xcodeproj using XcodeGen" \
	"make build-app   Build a signed Release app (requires signing env vars)" \
	"make notarize-app Notarize and staple the signed Release app (requires notary env vars)" \
	"make package-app Build and zip a signed Release app (requires signing env vars)" \
	"make package-dmg Build a signed DMG, optionally notarized if notary env vars are set" \
	"make clean-app   Remove generated build artifacts and the generated Xcode project"

try-local:
	./scripts/try_local.sh --install-tools

demo-vault:
	./scripts/generate_demo_vault.sh

docs-screenshots:
	./scripts/generate_doc_screenshots.sh

xcodeproj:
	./scripts/generate_xcode_project.sh

build-app: xcodeproj
	./scripts/build_app.sh

notarize-app: xcodeproj
	./scripts/notarize_release_app.sh

package-app: xcodeproj
	./scripts/package_release_app.sh

package-dmg: xcodeproj
	./scripts/package_release_dmg.sh

clean-app:
	rm -rf build Obviewer.xcodeproj
