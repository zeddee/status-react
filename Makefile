.PHONY: clean setup react-native test release

help: ##@other Show this help
	@perl -e '$(HELP_FUN)' $(MAKEFILE_LIST)

DO_SPACE_URL = https://status-go.ams3.digitaloceanspaces.com
GITHUB_URL = https://github.com/status-im/status-go/releases
RCTSTATUS_DIR = modules/react-native-status/ios/RCTStatus
ANDROID_LIBS_DIR = android/app/libs
STATUS_GO_VER = $(shell cat STATUS_GO_VERSION)

STATUS_GO_IOS_ARCH = $(RCTSTATUS_DIR)/status-go-ios-$(STATUS_GO_VER).zip
STATUS_GO_DRO_ARCH = $(ANDROID_LIBS_DIR)/status-go-$(STATUS_GO_VER).aar

OS := $(shell uname)

# This is a code for automatic help generator.
# It supports ANSI colors and categories.
# To add new item into help output, simply add comments
# starting with '##'. To add category, use @category.
GREEN  := $(shell tput -Txterm setaf 2)
WHITE  := $(shell tput -Txterm setaf 7)
YELLOW := $(shell tput -Txterm setaf 3)
RESET  := $(shell tput -Txterm sgr0)
HELP_FUN = \
		   %help; \
		   while(<>) { push @{$$help{$$2 // 'options'}}, [$$1, $$3] if /^([a-zA-Z\-]+)\s*:.*\#\#(?:@([a-zA-Z\-]+))?\s(.*)$$/ }; \
		   print "Usage: make [target]\n\n"; \
		   for (sort keys %help) { \
			   print "${WHITE}$$_:${RESET}\n"; \
			   for (@{$$help{$$_}}) { \
				   $$sep = " " x (32 - length $$_->[0]); \
				   print "  ${YELLOW}$$_->[0]${RESET}$$sep${GREEN}$$_->[1]${RESET}\n"; \
			   }; \
			   print "\n"; \
		   }

__toolversion = $(shell $(GIT_ROOT)/scripts/toolversion $(1))

# Main targets

clean: ##@prepare Remove all output folders
	git clean -dxf -f

setup: ##@prepare Install all the requirements for status-react
	@./scripts/setup

shell: ##@prepare Enter into a preconfigured shell
ifndef IN_NIX_SHELL
	@echo "Configuring Nix shell..."
	@nix-shell
else
	@echo "Nix shell is already active"
endif

prepare-desktop: ##@prepare Install desktop platform dependencies and prepare workspace
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	scripts/prepare-for-platform.sh desktop
	yarn install --frozen-lockfile
endif

$(STATUS_GO_IOS_ARCH):
	@echo "Downloading status-go artifact from DigitalOcean Bucket"; \
	curl --fail --silent --location \
		"${DO_SPACE_URL}/status-go-ios-$(STATUS_GO_VER).zip" \
		--output "$(STATUS_GO_IOS_ARCH)"; \
	if [ $$? -ne 0 ]; then \
		echo "Failed to download from DigitalOcean Bucket, checking GitHub..."; \
		curl --fail --silent --location \
			"$(GITHUB_URL)/download/$(STATUS_GO_VER)/status-go-ios.zip" \
			--output "$(STATUS_GO_IOS_ARCH)"; \
		if [ $$? -ne 0 ]; then \
			echo "Failed to download from GitHub!"; \
			echo "Please check the contents of your STATUS_GO_VERSION are correct."; \
			echo "Verify the version has been uploaded:"; \
			echo " * $(DO_SPACE_URL)/index.html"; \
			echo " * $(GITHUB_URL)"; \
			exit 1; \
		fi \
	fi

$(STATUS_GO_DRO_ARCH):
	mkdir -p $(ANDROID_LIBS_DIR)
	@echo "Downloading status-go artifact from DigitalOcean Bucket"; \
	curl --fail --silent --location \
		"${DO_SPACE_URL}/status-go-android-$(STATUS_GO_VER).aar" \
		--output "$(STATUS_GO_DRO_ARCH)"; \
	if [ $$? -ne 0 ]; then \
		echo "Failed to download from DigitalOcean Bucket, checking GitHub..."; \
		curl --fail --silent --location \
			"$(GITHUB_URL)/download/$(STATUS_GO_VER)/status-go-android.aar" \
			--output "$(STATUS_GO_DRO_ARCH)"; \
		if [ $$? -ne 0 ]; then \
			echo "Failed to download from GitHub!"; \
		fi \
	fi

prepare-ios: $(STATUS_GO_IOS_ARCH) ##@prepare Install and prepare iOS-specific dependencies
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	scripts/prepare-for-platform.sh ios
	yarn install --frozen-lockfile
	unzip -q -o "$(STATUS_GO_IOS_ARCH)" -d "$(RCTSTATUS_DIR)"
ifeq ($(OS),Darwin)
	cd ios && pod install
endif
endif

prepare-android: $(STATUS_GO_DRO_ARCH) ##@prepare Install and prepare Android-specific dependencies
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	scripts/prepare-for-platform.sh android
	yarn install --frozen-lockfile
	cd android && ./gradlew react-native-android:installArchives
endif

prepare-mobile: prepare-android prepare-ios ##@prepare Install and prepare mobile platform specific dependencies

#----------------
# Release builds
#----------------
release: release-android release-ios ##@build build release for Android and iOS

release-android: prod-build-android ##@build build release for Android
ifdef IN_NIX_SHELL
	react-native run-android --variant=release
endif

release-ios: prod-build-ios ##@build build release for iOS release
ifdef IN_NIX_SHELL
	@echo "Build in XCode, see https://status.im/build_status/ for instructions"
endif

release-desktop: prod-build-desktop ##@build build release for desktop release
ifdef IN_NIX_SHELL
	scripts/build-desktop.sh
endif

release-windows-desktop: prod-build-desktop ##@build build release for desktop release
ifdef IN_NIX_SHELL
	TARGET_SYSTEM_NAME=Windows scripts/build-desktop.sh
endif

prod-build:
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	scripts/run-environment-check.sh android
	scripts/run-environment-check.sh ios
	lein prod-build
endif

prod-build-android:
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	rm ./modules/react-native-status/android/libs/status-im/status-go/local/status-go-local.aar 2> /dev/null || true
	scripts/run-environment-check.sh android
	lein prod-build-android
endif

prod-build-ios:
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	rm -r ./modules/react-native-status/ios/RCTStatus/Statusgo.framework/ 2> /dev/null || true
	scripts/run-environment-check.sh ios
	lein prod-build-ios
endif

full-prod-build: ##@build build prod for both Android and iOS
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	./scripts/bundle-status-go.sh ios android
	$(MAKE) prod-build
	rm -r ./modules/react-native-status/ios/RCTStatus/Statusgo.framework/ 2> /dev/null || true
	rm ./modules/react-native-status/android/libs/status-im/status-go/local/status-go-local.aar 2> /dev/null
endif

prod-build-desktop:
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	git clean -qdxf -f ./index.desktop.js desktop/
	scripts/run-environment-check.sh desktop
	lein prod-build-desktop
endif

#--------------
# REPL
# -------------

_watch-%: ##@watch Start development for device
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	$(eval SYSTEM := $(word 2, $(subst -, , $@)))
	$(eval DEVICE := $(word 3, $(subst -, , $@)))
	scripts/run-environment-check.sh $(SYSTEM)
	clj -R:dev build.clj watch --platform $(SYSTEM) --$(SYSTEM)-device $(DEVICE)
endif

watch-ios-real: _watch-ios-real ##@watch Start development for iOS real device

watch-ios-simulator: _watch-ios-simulator ##@watch Start development for iOS simulator

watch-android-real: _watch-android-real ##@watch Start development for Android real device

watch-android-avd: _watch-android-avd ##@watch Start development for Android AVD

watch-android-genymotion: _watch-android-genymotion ##@watch Start development for Android Genymotion

watch-desktop: ##@watch Start development for Desktop
	scripts/run-environment-check.sh desktop
	clj -R:dev build.clj watch --platform desktop

#--------------
# Run
# -------------
_run-%:
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	$(eval SYSTEM := $(word 2, $(subst -, , $@)))
	scripts/run-environment-check.sh $(SYSTEM)
	react-native run-$(SYSTEM)
endif

run-android: _run-android ##@run Run Android build

run-desktop: _run-desktop ##@run Run Desktop build

SIMULATOR=
run-ios: ##@run Run iOS build
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	scripts/run-environment-check.sh ios
ifneq ("$(SIMULATOR)", "")
	react-native run-ios --simulator="$(SIMULATOR)"
else
	react-native run-ios
endif
endif

#--------------
# Tests
#--------------

test: ##@test Run tests once in NodeJS
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	lein with-profile test doo node test once
endif

test-auto: ##@test Run tests in interactive (auto) mode in NodeJS
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	lein with-profile test doo node test
endif

#--------------
# Other
#--------------
react-native: ##@other Start react native packager
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	@scripts/start-react-native.sh
endif

geth-connect: ##@other Connect to Geth on the device
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	adb forward tcp:8545 tcp:8545
	build/bin/geth attach http://localhost:8545
endif

android-ports: ##@other Add proxies to Android Device/Simulator
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	adb reverse tcp:8081 tcp:8081
	adb reverse tcp:3449 tcp:3449
	adb reverse tcp:4567 tcp:4567
	adb forward tcp:5561 tcp:5561
endif

android-logcat:
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	adb logcat | grep -e StatusModule -e ReactNativeJS -e StatusNativeLogs
endif

_list:
	@$(MAKE) -pRrq -f $(lastword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | egrep -v -e '^[^[:alnum:]]' -e '^$@$$'

_unknown-startdev-target-%:
	@ echo "Unknown target device '$*'. Supported targets:"
	@ ${MAKE} _list | grep "watch-" | sed s/watch-/startdev-/
	@ exit 1

_startdev-%:
ifndef IN_NIX_SHELL
	@echo "Please run '$(MAKE) shell' first"
else
	$(eval SYSTEM := $(word 2, $(subst -, , $@)))
	$(eval DEVICE := $(word 3, $(subst -, , $@)))
	$(MAKE) prepare-${SYSTEM} || $(MAKE) _unknown-startdev-target-$@
	@ if [ -z "$(DEVICE)" ]; then \
		$(MAKE) watch-$(SYSTEM) || $(MAKE) _unknown-startdev-target-$@; \
	else \
		$(MAKE) watch-$(SYSTEM)-$(DEVICE) || $(MAKE) _unknown-startdev-target-$@; \
	fi
endif

startdev-android-avd: _startdev-android-avd
startdev-android-genymotion: _startdev-android-genymotion
startdev-android-real: _startdev-android-real
startdev-desktop: _startdev-desktop
startdev-ios-real: _startdev-ios-real
startdev-ios-simulator: _startdev-ios-simulator
