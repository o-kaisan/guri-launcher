# guri-launcher

Android 向けランチャーアプリの開発基盤です。現在は Kotlin と Jetpack Compose で、アプリ名を表示する最小構成を提供しています。

## 必要な環境

- JDK 25
- Android Studio（または Android SDK。compileSdk 35、Android 17 emulator）

## ローカルでの確認

Android Studio でリポジトリのルートを開くか、SDK の場所を `local.properties` の `sdk.dir` または `ANDROID_HOME` に設定して実行します。

```shell
make test
make lint
make assemble-debug
```

3 つの確認と Android emulator script のテストをまとめて実行する場合は `make check` を使います。利用可能なコマンドは `make help` で確認できます。

Debug APK は `app/build/outputs/apk/debug/app-debug.apk` に生成されます。Pull Request と `main` への push では同じ確認を CI で実行します。`vX.Y.Z` タグでは、バージョンを含む名前の APK と自動生成したリリースノートを GitHub Release へ公開します。

## Android 17 emulator での確認

Test Android Apps プラグインで端末操作を検証するには、Linux x86_64、JDK 25、`curl`、`unzip`、`libx11-xcb1` とAndroid SDK用の空き容量が必要です。環境設定はcommand-line tools、platform-tools、emulator、compileSdk 35、Build Tools 36、Android 17（API 37.0）Google APIs x86_64 system imageを導入します。

```shell
make android-sdk
```

非対話の自動化環境向けに、この処理は `sdkmanager --licenses` へ同意を入力します。ライセンスを確認して同意できる環境でのみ実行してください。`ANDROID_SDK_ROOT`（または `ANDROID_HOME`）が未設定の場合は `$HOME/Android/Sdk` を使います。

AVD の作成と headless 起動は次のコマンドで行います。

```shell
make android-emulator-start
```

`guri_api_37` が存在しない場合だけPixel 6プロファイルとAndroid 17 Google APIs x86_64 imageで作成します。ローカルのheadless起動はGPU off、`-no-window`、snapshot無効を使用します。Compose GUI起動はXvfb内でwindowを表示し、Mesaのhost rendererで描画します。既定の `EMULATOR_ACCELERATION=auto` はKVMが利用できれば `-accel on`、それ以外は `-accel off` を選びます。既定では起動完了を最大300秒待ち、`BOOT_TIMEOUT_SECONDS` で変更できます。

Test Android Apps プラグインからは、起動後に通常どおり `adb -e` を使えます。debug APK の build、置換 install、`MainActivity` 起動はまとめて確認できます。

```shell
make android-emulator-devices
make android-emulator-install
```

`start-emulator.sh` は `adb wait-for-device` と `sys.boot_completed` の両方を待ちます。起動失敗またはタイムアウト時は adb、プロセス、emulator log、端末 property を出力し、このスクリプトが起動した emulator を終了します。検証後は次のコマンドで停止してください。

```shell
make android-emulator-stop
```


## Android 17 emulator コンテナ

KVM 対応 Linux ホストでは、Android 17（API 37.0）emulatorをブラウザーで操作できます。1コマンドでimage build、emulator起動待機、APK build、install、`MainActivity` 起動まで行います。Docker image はJDK 25、compileSdk 35、Build Tools 36、Android 17 Google APIs x86_64 system image、Xvfb、noVNCを含みます。秘密情報やGitHub tokenはbuild argやimage layerへ渡さないでください。

### Compose image を build する

```shell
make android-container-build
docker image inspect guri-launcher-android-emulator:api37 --format '{{.Size}}'
```

imageはAndroid SDK、x86_64 system image、emulator、JDK、noVNCを含むため、数GBの容量を見込んでください。Dockerfileはbase image、command-line tools、build-tools、platform-tools、emulator、compile platform、Android 17 system imageのrevisionを検証します。

### SDK ライセンス

Docker build は `sdkmanager --licenses` へ非対話で同意したうえで SDK package を導入します。利用者は、build または配布前に [Android SDK License Agreement](https://developer.android.com/studio/terms) と各 system image に適用される Google APIs の条件を確認し、同意できる場合だけ image を利用してください。image の再配布可否もこれらの条件に従います。

### 1コマンドで起動・表示する

Composeの `android-emulator` serviceは `/dev/kvm` を渡し、専用AVD `guri_docker_api_37` を作成します。APKをbuildしてからXvfb上に実際のemulator windowを起動し、noVNCで配信します。healthcheckがAndroid bootとnoVNCの両方を確認した後、APKをinstallして起動します。

```shell
make android-container-run
```

完了後、ブラウザーで [http://localhost:6080](http://localhost:6080) を開きます。ポートはlocalhostだけに公開されます。別ポートを使う場合は `ANDROID_EMULATOR_GUI_PORT=6081 make android-container-run` とします。

`/dev/kvm` が存在しない場合、既定の `auto` モードは明確なエラーで停止します。権限不足の場合も、ホスト側で `/dev/kvm` を利用できるようにしてから再実行してください。

### KVM なしで明示的に起動する

software emulation は非常に低速です。次のように `off` を明示した場合だけ `-accel off` で続行します。`auto` と `off` 以外の外部入力は拒否し、コマンド文字列を `eval` しません。

```shell
ANDROID_EMULATOR_ACCELERATION=off ./scripts/android/run-in-container.sh
docker compose --profile software exec android-emulator-software adb devices
```

### Test Android Apps プラグインから利用する

プラグインの terminal command（または検証コマンド）を、稼働中コンテナを対象とする次の形式に設定します。これにより plugin からも同一の SDK、Gradle workspace、`adb` server、emulator を利用できます。

```shell
docker compose exec android-emulator \
  bash -lc './scripts/android/install-and-launch.sh'
```

個別操作が必要なら、同じ prefix の後ろで `adb devices`、`adb shell`、`./gradlew test` などを実行します。ホスト側の `adb` ではなく、必ずコンテナ内の `adb` を使用してください。
software emulation で起動した場合は、`docker compose --profile software exec android-emulator-software` を prefix に使います。

### 停止・削除する

```shell
make android-container-down
docker volume rm guri-launcher-android-avd       # AVD も破棄する場合のみ
docker image rm guri-launcher-android-emulator:api37
```

AVD を次回も使う場合は named volume を削除しません。再開時は `make android-container-run` を実行してください。

## 開発への参加

設計、実装、テスト、セキュリティ確認、Pull Request の進め方は [開発ルール](.codex/DEVELOPMENT.md) を参照してください。
