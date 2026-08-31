# guri-launcher

Android 向けランチャーアプリの開発基盤です。現在は Kotlin と Jetpack Compose で、アプリ名を表示する最小構成を提供しています。

## 必要な環境

- JDK 25
- Android Studio（または Android SDK。API 35）

## ローカルでの確認

Android Studio でリポジトリのルートを開くか、SDK の場所を `local.properties` の `sdk.dir` または `ANDROID_HOME` に設定して実行します。

```shell
make test
make lint
make assemble-debug
```

3 つの確認と Android emulator script のテストをまとめて実行する場合は `make check` を使います。利用可能なコマンドは `make help` で確認できます。

Debug APK は `app/build/outputs/apk/debug/app-debug.apk` に生成されます。Pull Request と `main` への push では同じ確認を CI で実行します。`vX.Y.Z` タグでは、バージョンを含む名前の APK と自動生成したリリースノートを GitHub Release へ公開します。

## API 35 emulator での確認

Test Android Apps プラグインで端末操作を検証するには、Linux x86_64、JDK 25、`curl`、`unzip`、emulator の headless backend が必要とする `libx11-xcb1` と Android SDK 用の空き容量が必要です。リポジトリの環境設定 `.codex/environments/setup.sh` は次のスクリプトを呼び出し、command-line tools、platform-tools、emulator、API 35 platform、Google APIs x86_64 system image を導入します。

```shell
make android-sdk
```

非対話の自動化環境向けに、この処理は `sdkmanager --licenses` へ同意を入力します。ライセンスを確認して同意できる環境でのみ実行してください。`ANDROID_SDK_ROOT`（または `ANDROID_HOME`）が未設定の場合は `$HOME/Android/Sdk` を使います。

AVD の作成と headless 起動は次のコマンドで行います。

```shell
make android-emulator-start
```

`guri_api_35` が存在しない場合だけ Pixel 6 プロファイルと API 35 Google APIs x86_64 image で作成します。既存 AVD は再作成しません。RAM 2 GiB、2 CPU、GPU off（Vulkan も無効）、`-no-window -no-audio -no-boot-anim`、snapshot 無効を明示します。既定の `EMULATOR_ACCELERATION=auto` では `/dev/kvm` の存在と読み書き権限、および `emulator -accel-check` の成功を確認し、KVM が利用できれば `-accel on`、それ以外は `-accel off` で起動します。選択結果は起動時に表示されます。必要に応じて `EMULATOR_ACCELERATION=on` または `off` で明示指定でき、それ以外の値は拒否されます。ソフトウェアエミュレーションは非常に遅く、CPU によっては実用的な時間内に起動を完了できません。既定では起動完了を最大 300 秒待ち、必要な場合は 1 から 9999 までの整数秒を `BOOT_TIMEOUT_SECONDS` に設定できます。実機相当の継続的な検証には KVM 対応 worker を推奨します。

Test Android Apps プラグインからは、起動後に通常どおり `adb -e` を使えます。debug APK の build、置換 install、`MainActivity` 起動はまとめて確認できます。

```shell
make android-emulator-devices
make android-emulator-install
```

`start-emulator.sh` は `adb wait-for-device` と `sys.boot_completed` の両方を待ちます。起動失敗またはタイムアウト時は adb、プロセス、emulator log、端末 property を出力し、このスクリプトが起動した emulator を終了します。検証後は次のコマンドで停止してください。

```shell
make android-emulator-stop
```


## Android API 35 emulator コンテナ

KVM 対応 Linux ホストでは、API 35 emulator、APK の build、install、`MainActivity` の起動をコンテナ内で再現できます。Docker image は JDK 25、Android command-line tools、platform-tools、emulator、API 35 platform/build-tools、Google APIs x86_64 system image を含みます。秘密情報や GitHub token は build arg や image layer へ渡さないでください。`.dockerignore` もローカル設定、署名素材、build 出力を build context から除外します。

### Image を build する

```shell
docker build -f docker/android-emulator/Dockerfile \
  -t guri-launcher-android-emulator:api35 .
docker image inspect guri-launcher-android-emulator:api35 --format '{{.Size}}'
```

image は Android SDK、x86_64 system image、emulator、JDK を含むため、圧縮前でおおむね 3～5 GB を見込んでください。実際のサイズは二つ目のコマンドで確認します。Dockerfile は base image、command-line tools、build-tools、platform-tools、emulator、API 35 platform、system image の revision を固定しています。`sdkmanager` の配布版が固定値から変わった場合は検証を失敗させ、意図しない更新を image に取り込みません。

### SDK ライセンス

Docker build は `sdkmanager --licenses` へ非対話で同意したうえで SDK package を導入します。利用者は、build または配布前に [Android SDK License Agreement](https://developer.android.com/studio/terms) と各 system image に適用される Google APIs の条件を確認し、同意できる場合だけ image を利用してください。image の再配布可否もこれらの条件に従います。

### KVM で起動・検証する

`run-in-container.sh` は `/dev/kvm` をコンテナへ渡し、専用 AVD `guri_docker_api_35` を作成します。リポジトリは `/workspace`、AVD は named volume `guri-launcher-android-avd` に mount されます。既存のローカル AVD `guri_api_35` は変更しません。boot 後に同じコンテナ内で `assembleDebug`、`adb install -r`、`MainActivity` 起動まで実行します。

```shell
./scripts/android/run-in-container.sh
docker exec guri-launcher-android-emulator adb devices
```

`/dev/kvm` が存在しない場合、既定の `auto` モードは明確なエラーで停止します。権限不足の場合も、ホスト側で `/dev/kvm` を利用できるようにしてから再実行してください。

### KVM なしで明示的に起動する

software emulation は非常に低速です。次のように `off` を明示した場合だけ `-accel off` で続行します。`auto` と `off` 以外の外部入力は拒否し、コマンド文字列を `eval` しません。

```shell
ANDROID_EMULATOR_ACCELERATION=off ./scripts/android/run-in-container.sh
```

### Test Android Apps プラグインから利用する

プラグインの terminal command（または検証コマンド）を、稼働中コンテナを対象とする次の形式に設定します。これにより plugin からも同一の SDK、Gradle workspace、`adb` server、emulator を利用できます。

```shell
docker exec -w /workspace guri-launcher-android-emulator \
  bash -lc './scripts/android/install-and-launch.sh'
```

個別操作が必要なら、同じ prefix の後ろで `adb devices`、`adb shell`、`./gradlew test` などを実行します。ホスト側の `adb` ではなく、必ずコンテナ内の `adb` を使用してください。

### 停止・削除する

```shell
docker stop guri-launcher-android-emulator
docker rm guri-launcher-android-emulator
docker volume rm guri-launcher-android-avd       # AVD も破棄する場合のみ
docker image rm guri-launcher-android-emulator:api35
```

AVD を次回も使う場合は named volume を削除しません。停止済み container が残っている場合は `docker start guri-launcher-android-emulator` で再開できますが、emulator の再起動を含む確実な検証には container を削除して runner を再実行してください。

## 開発への参加

設計、実装、テスト、セキュリティ確認、Pull Request の進め方は [開発ルール](.codex/DEVELOPMENT.md) を参照してください。
