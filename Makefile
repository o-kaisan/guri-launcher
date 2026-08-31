SHELL := /bin/bash

GRADLEW := ./gradlew
ANDROID_SCRIPTS := ./scripts/android
ANDROID_SDK_ROOT ?= $(if $(ANDROID_HOME),$(ANDROID_HOME),$(HOME)/Android/Sdk)

export ANDROID_SDK_ROOT
export ANDROID_HOME := $(ANDROID_SDK_ROOT)
export PATH := $(ANDROID_SDK_ROOT)/platform-tools:$(ANDROID_SDK_ROOT)/emulator:$(PATH)

.DEFAULT_GOAL := help

.PHONY: help test lint assemble-debug check \
	android-sdk android-emulator-start android-emulator-install \
	android-emulator-devices android-emulator-stop android-emulator-test

help: ## 利用できるコマンドを表示する
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  %-28s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

test: ## unit test を実行する
	$(GRADLEW) test

lint: ## Android lint を実行する
	$(GRADLEW) lint

assemble-debug: ## debug APK をビルドする
	$(GRADLEW) assembleDebug

check: test lint assemble-debug android-emulator-test ## unit test、lint、build、emulator script test を実行する

android-sdk: ## API 35 emulator 用 Android SDK を導入する
	$(ANDROID_SCRIPTS)/setup-sdk.sh

android-emulator-start: ## API 35 AVD を作成し headless で起動する
	$(ANDROID_SCRIPTS)/start-emulator.sh

android-emulator-install: ## debug APK をビルド、インストール、起動する
	$(ANDROID_SCRIPTS)/install-and-launch.sh

android-emulator-devices: ## adb で認識されている emulator を表示する
	adb devices -l

android-emulator-stop: ## API 35 emulator を停止する
	$(ANDROID_SCRIPTS)/stop-emulator.sh

android-emulator-test: ## Android emulator script のテストを実行する
	$(ANDROID_SCRIPTS)/test-scripts.sh
