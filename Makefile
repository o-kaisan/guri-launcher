SHELL := /bin/bash

GRADLEW := ./gradlew
ANDROID_SCRIPTS := ./scripts/android
RELEASE_SCRIPTS := ./scripts/release
ANDROID_SDK_ROOT ?= $(if $(ANDROID_HOME),$(ANDROID_HOME),$(HOME)/Android/Sdk)

export ANDROID_SDK_ROOT
export ANDROID_HOME := $(ANDROID_SDK_ROOT)
export PATH := $(ANDROID_SDK_ROOT)/platform-tools:$(ANDROID_SDK_ROOT)/emulator:$(PATH)

.DEFAULT_GOAL := help

.PHONY: help test lint assemble-debug check \
	android-sdk android-emulator-start android-emulator-install \
	android-emulator-devices android-emulator-stop android-emulator-test \
	android-container-build android-container-run android-container-down \
	release-test release-signing-setup

help: ## 利用できるコマンドを表示する
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-28s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

test: ## unit test を実行する
	$(GRADLEW) test

lint: ## Android lint を実行する
	$(GRADLEW) lint

assemble-debug: ## debug APK をビルドする
	$(GRADLEW) assembleDebug

check: test lint assemble-debug android-emulator-test release-test ## unit test、lint、build、script test を実行する

release-test: ## Release用scriptのテストを実行する
	$(RELEASE_SCRIPTS)/test-release-metadata.sh
	$(RELEASE_SCRIPTS)/test-configure-signing.sh
	$(RELEASE_SCRIPTS)/test-verify-release-tag.sh

release-signing-setup: ## Release署名鍵を作成してGitHub Secretsへ登録する
	$(RELEASE_SCRIPTS)/configure-signing.sh

android-sdk: ## Android 17 emulator 用 Android SDK を導入する
	$(ANDROID_SCRIPTS)/setup-sdk.sh

android-emulator-start: ## Android 17 AVD を作成し headless で起動する
	$(ANDROID_SCRIPTS)/start-emulator.sh

android-emulator-install: ## debug APK をビルド、インストール、起動する
	$(ANDROID_SCRIPTS)/install-and-launch.sh

android-emulator-devices: ## adb で認識されている emulator を表示する
	adb devices -l

android-emulator-stop: ## Android 17 emulator を停止する
	$(ANDROID_SCRIPTS)/stop-emulator.sh

android-emulator-test: ## Android emulator script のテストを実行する
	$(ANDROID_SCRIPTS)/test-scripts.sh

android-container-build: ## Android emulator の Compose image を build する
	docker compose build android-emulator

android-container-run: ## Android 17 GUI emulator を起動しアプリを導入する
	$(ANDROID_SCRIPTS)/run-in-container.sh

android-container-down: ## Compose の emulator container を停止・削除する
	docker compose --profile software down
