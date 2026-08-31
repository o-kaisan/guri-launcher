# guri-launcher

Android 向けランチャーアプリの開発基盤です。現在は Kotlin と Jetpack Compose で、アプリ名を表示する最小構成を提供しています。

## 必要な環境

- JDK 25
- Android Studio（または Android SDK。API 35）

## ローカルでの確認

Android Studio でリポジトリのルートを開くか、SDK の場所を `local.properties` の `sdk.dir` または `ANDROID_HOME` に設定して実行します。

```shell
./gradlew test
./gradlew lint
./gradlew assembleDebug
```

Debug APK は `app/build/outputs/apk/debug/app-debug.apk` に生成されます。Pull Request と `main` への push では同じ確認を CI で実行します。`vX.Y.Z` タグでは、バージョンを含む名前の APK と自動生成したリリースノートを GitHub Release へ公開します。

## API 35 emulator での確認

Test Android Apps プラグインで端末操作を検証するには、Linux x86_64、JDK 25、`curl`、`unzip`、emulator の headless backend が必要とする `libx11-xcb1` と Android SDK 用の空き容量が必要です。リポジトリの環境設定 `.codex/environments/setup.sh` は次のスクリプトを呼び出し、command-line tools、platform-tools、emulator、API 35 platform、Google APIs x86_64 system image を導入します。

```shell
./scripts/android/setup-sdk.sh
```

非対話の自動化環境向けに、この処理は `sdkmanager --licenses` へ同意を入力します。ライセンスを確認して同意できる環境でのみ実行してください。`ANDROID_SDK_ROOT`（または `ANDROID_HOME`）が未設定の場合は `$HOME/Android/Sdk` を使います。

AVD の作成と headless 起動は次のコマンドで行います。

```shell
./scripts/android/start-emulator.sh
```

`guri_api_35` が存在しない場合だけ Pixel 6 プロファイルと API 35 Google APIs x86_64 image で作成します。既存 AVD は再作成しません。RAM 2 GiB、2 CPU、GPU off（Vulkan も無効）、`-no-window -no-audio -no-boot-anim`、snapshot 無効を明示し、KVM がない環境でも動くよう `-accel off` で起動します。ソフトウェアエミュレーションは非常に遅く、CPU によっては実用的な時間内に起動を完了できません。既定では起動完了を最大 300 秒待ち、必要な場合は 1 から 9999 までの整数秒を `BOOT_TIMEOUT_SECONDS` に設定できます。実機相当の継続的な検証には KVM 対応 worker を推奨します。

Test Android Apps プラグインからは、起動後に通常どおり `adb -e` を使えます。debug APK の build、置換 install、`MainActivity` 起動はまとめて確認できます。

```shell
adb devices
./scripts/android/install-and-launch.sh
```

`start-emulator.sh` は `adb wait-for-device` と `sys.boot_completed` の両方を待ちます。起動失敗またはタイムアウト時は adb、プロセス、emulator log、端末 property を出力し、このスクリプトが起動した emulator を終了します。検証後は次のコマンドで停止してください。

```shell
./scripts/android/stop-emulator.sh
```

## 開発への参加

設計、実装、テスト、セキュリティ確認、Pull Request の進め方は [開発ルール](.codex/DEVELOPMENT.md) を参照してください。
