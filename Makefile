.PHONY: help try-local xcodeproj build-app package-app clean-app

help:
	@printf '%s\n' \
	"make try-local   Generate the Xcode project and open it for the easiest first run" \
	"make xcodeproj   Generate Obviewer.xcodeproj using XcodeGen" \
	"make build-app   Build a signed Release app (requires signing env vars)" \
	"make package-app Build and zip a signed Release app (requires signing env vars)" \
	"make clean-app   Remove generated build artifacts and the generated Xcode project"

try-local:
	./scripts/try_local.sh --install-tools

xcodeproj:
	./scripts/generate_xcode_project.sh

build-app: xcodeproj
	./scripts/build_app.sh

package-app: xcodeproj
	./scripts/package_release_app.sh

clean-app:
	rm -rf build Obviewer.xcodeproj
