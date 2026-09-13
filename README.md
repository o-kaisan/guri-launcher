# guri-launcher

Flutter で実装した Android 向けランチャーアプリです。画面の「デフォルトのホームに設定」から OS 標準 UI で HOME アプリに設定できます。Android 固有処理は MethodChannel の infrastructure 実装に限定しています。

HOME 設定の動作と検証手順は [デフォルト HOME の検証](docs/testing/default-home.md) を参照してください。

## 必要な環境

- Flutter stable
- Android Studio（または Android SDK）

## ローカルでの確認

VS Code でローカルの Android エミュレーターを選択し、既存の `guri-launcher` 起動構成でデバッグします。

Flutter と Android SDK を設定して実行します。

```shell
make test
make lint
make assemble-debug
```

3 つの確認と Android emulator script のテストをまとめて実行する場合は `make check` を使います。利用可能なコマンドは `make help` で確認できます。

Debug APK は `build/app/outputs/flutter-apk/app-debug.apk` に生成されます。Pull Request と `main` への push では同じ確認を CI で実行します。

## スマートフォンへ配布するAPK

`vX.Y.Z` タグをpushすると、同じリリース鍵で署名されたAPKと自動生成したRelease NotesをGitHub Releaseへ公開します。Assetsのファイル名は `guri-launcher-vX.Y.Z.apk` です。スマートフォンで[Releases](https://github.com/o-kaisan/guri-launcher/releases)を開き、APKを直接ダウンロードしてインストールできます。初回だけ、ダウンロードに使用したブラウザーまたはファイル管理アプリに「不明なアプリのインストール」の許可が必要です。

同じ署名鍵と、タグから生成されるより大きな `versionCode` を使うため、以前のAPKを削除せず上書き更新できます。`v1.2.3` は `versionName=1.2.3`、`versionCode=1002003` になります。タグは先頭ゼロのない `vX.Y.Z` 形式とし、minorとpatchはそれぞれ999以下にします。古いバージョンへ戻す場合は通常の上書きインストールができません。

開発用のDebug APKがすでに入っている端末では署名が異なるため、最初のRelease APKを入れる前に一度だけDebug APKをアンインストールします。それ以降のRelease APKは上書き更新できます。

### 初回だけ行う署名設定

JDKの `keytool` と、リポジトリ管理権限を持つ本人としてログイン済みのGitHub CLI `gh` があるPCで次を実行します。

```shell
make release-signing-setup
```

このコマンドは、ログイン中のGitHubユーザーを必須承認者にした保護Environment `release` を作成します。16文字以上のパスワードを入力すると、既定では `~/.config/guri-launcher/release.keystore` にリリース鍵を作成し、次のEnvironment Secretsを登録します。パスワードは画面やログへ出力しません。

- `ANDROID_RELEASE_KEYSTORE_BASE64`
- `ANDROID_RELEASE_KEYSTORE_PASSWORD`
- `ANDROID_RELEASE_KEY_ALIAS`
- `ANDROID_RELEASE_KEY_PASSWORD`

既存の `release` Environment は承認者、待機時間、自己承認禁止、ブランチ制限を変更せず再利用します。必須承認者が未設定の場合は停止するため、GitHub側で設定してから再実行してください。新規Environmentはパスワードと署名鍵の検証後に作成します。

さらに、秘密情報ではない公開証明書の指紋をEnvironment Variable `ANDROID_RELEASE_CERT_SHA256` に登録します。再実行時はこの指紋をローカル鍵と照合し、異なる署名鍵によるSecretsの置換を防ぎます。Release Workflowも完成したAPKの署名指紋をこの値と照合し、不一致なら公開しません。

リリース鍵とパスワードを失うと、インストール済みアプリを上書き更新できません。リポジトリには追加せず、両方を安全な別の場所にもバックアップしてください。Secrets登録だけをやり直す場合は、同じ保存先とパスワードでもう一度コマンドを実行します。保存先を変更する場合は、リポジトリ外のパスを指定します。

```shell
GURI_RELEASE_KEYSTORE_PATH=/安全な保存先/release.keystore \
  make release-signing-setup
```

`release` Environmentに署名Secretsまたは証明書指紋があるのに指定した鍵が見つからない場合、別鍵による誤上書きを防ぐため処理は停止します。まず元の鍵をバックアップから復元してください。既存端末を更新できなくなることを承知して意図的に鍵を作り直す場合だけ、次を実行して確認欄に `ROTATE RELEASE KEY` と入力します。

```shell
GURI_ALLOW_RELEASE_KEY_ROTATION=true make release-signing-setup
```

### リリースする

署名設定後、`main` のリリース対象コミットへタグを付けてpushします。

```shell
git switch main
git pull --ff-only
git tag -a v0.1.0 -m "Release v0.1.0"
git push origin v0.1.0
```

タグをpushするとRelease Workflowは `release` Environmentの承認待ちになります。GitHub Actionsの実行画面でタグと対象コミットが意図した `main` の内容であることを確認し、`Review deployments` から `Approve and deploy` を選びます。承認されるまで署名鍵のSecretsをジョブから読み取ることはできません。

承認後、Release WorkflowはTest、Lint、署名付きRelease APKのビルド、保存済み証明書指紋との署名照合を行います。すべて成功した場合だけGitHub Releaseを作成します。署名情報が不足している場合、タグが不正な場合、署名者が異なる場合、または処理中にタグの参照先が変わった場合は、APKを公開せず失敗します。同じタグのReleaseは上書きしないため、公開後のAPKも置き換えません。

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

`guri_api_37` が存在しない場合だけPixel 6プロファイルとAndroid 17 Google APIs x86_64 imageで作成します。ローカルのheadless起動はGPU off、`-no-window`、snapshot無効を使用します。既定の `EMULATOR_ACCELERATION=auto` はKVMが利用できれば `-accel on`、それ以外は `-accel off` を選びます。既定では起動完了を最大300秒待ち、`BOOT_TIMEOUT_SECONDS` で変更できます。

Test Android Apps プラグインからは、起動後に通常どおり `adb -e` を使えます。debug APK の build、置換 install、`MainActivity` 起動はまとめて確認できます。

```shell
make android-emulator-devices
make android-emulator-install
```

`start-emulator.sh` は `adb wait-for-device` と `sys.boot_completed` の両方を待ちます。起動失敗またはタイムアウト時は adb、プロセス、emulator log、端末 property を出力し、このスクリプトが起動した emulator を終了します。検証後は次のコマンドで停止してください。

```shell
make android-emulator-stop
```


## 開発への参加

設計、実装、テスト、セキュリティ確認、Pull Request の進め方は [開発ルール](.codex/DEVELOPMENT.md) を参照してください。
