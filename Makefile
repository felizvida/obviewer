.PHONY: xcodeproj build-app package-app clean-app

xcodeproj:
	./scripts/generate_xcode_project.sh

build-app: xcodeproj
	./scripts/build_app.sh

package-app: xcodeproj
	./scripts/package_release_app.sh

clean-app:
	rm -rf build Obviewer.xcodeproj
