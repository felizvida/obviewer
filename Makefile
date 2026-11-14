.PHONY: help publication-check renderer renderer-test package-adhoc try-local demo-vault benchmark-vault docs-screenshots xcodeproj build-app notarize-app package-app package-dmg clean-app

help:
	@printf '%s\n' \
	"make try-local   Generate the Xcode project and open it for the easiest first run" \
	"make demo-vault  Generate a rich sample Obsidian vault under build/SampleVault" \
	"make benchmark-vault Profile a vault; supports PROFILE, VAULT, FORMAT, OUTPUT, SUMMARY, and BUDGET env vars" \
	"make docs-screenshots Generate polished product screenshots under docs/images" \
	"make xcodeproj   Generate Obviewer.xcodeproj using XcodeGen" \
	"make build-app   Build a signed Release app (requires signing env vars)" \
	"make notarize-app Notarize and staple the signed Release app (requires notary env vars)" \
	"make package-app Build and zip a signed Release app (requires signing env vars)" \
	"make package-dmg Build a signed DMG, optionally notarized if notary env vars are set" \
	"make package-adhoc Build an ad-hoc signed DMG for colleagues (no Apple Developer ID needed)" \
	"make publication-check Scan tracked files against the publication policy (needs tesseract and pdftotext)" \
	"make renderer    Rebuild the offline reader bundle (needs Node and npm ci in Renderer/)" \
	"make renderer-test Run the renderer's Node tests" \
	"make clean-app   Remove generated build artifacts and the generated Xcode project"

try-local:
	./scripts/try_local.sh --install-tools

demo-vault:
	./scripts/generate_demo_vault.sh

benchmark-vault:
	./scripts/benchmark_vault.sh

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

publication-check:
	node scripts/publication-check.mjs --tracked

renderer:
	cd Renderer && npm ci --ignore-scripts && npm run build

renderer-test:
	cd Renderer && npm test

package-adhoc: xcodeproj
	OBVIEWER_CODE_SIGN_IDENTITY=- ./scripts/package_release_dmg.sh

clean-app:
	rm -rf build Obviewer.xcodeproj
