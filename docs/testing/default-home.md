# デフォルト HOME の検証（Issue #20）

## 動作

ホーム画面の「デフォルトのホームに設定」から、OS 標準の選択画面を開く。
API 29 以上では HOME role、API 26〜28 では HOME 設定を使用する。
起動や復帰だけでは要求画面を開かず、選択済みの場合も再要求しない。
拒否や設定画面の起動失敗後も、アプリの画面を利用できる。

Android API の参照:

- [RoleManager](https://developer.android.com/reference/android/app/role/RoleManager)
- [ACTION_HOME_SETTINGS](https://developer.android.com/reference/android/provider/Settings#ACTION_HOME_SETTINGS)

## 操作確認手順

専用エミュレーターで次を API 26 と API 29 以上に対して実行する。

1. debug APK をインストールし、アプリアイコンから起動する。HOME 選択画面が自動表示されないことを確認する。
2. 「デフォルトのホームに設定」を押す。OS 標準 UI に guri-launcher が候補として現れることを確認する。
3. 戻る操作またはキャンセルで拒否する。画面に未設定状態が表示され、再度操作できることを確認する。
4. 再要求して guri-launcher を選ぶ。戻った画面に選択済み状態が表示されることを確認する。
5. HOME 操作で guri-launcher が起動することを確認する。設定要求が繰り返されないことを確認する。
6. OS 設定から別の HOME に変更し、アプリアイコンから戻る。未設定状態へ更新されることを確認する。
7. Activity を再作成しても OS の実際の HOME 選択状態が表示されることを確認する。

## セキュリティ確認

- HOME 変更はユーザーの明示操作と OS 標準 UI を通す。
- 権限、広範な package visibility、外部依存を追加しない。
- HOME/LAUNCHER は同じ既存 Activity の独立した intent filter とする。
- アプリ名一覧、選択履歴、例外の詳細をログや永続ストレージへ出力しない。

## 検証記録

2026-09-13、#35（PR #34 の不要実装レビュー）。
- Dart全実装、Kotlin、Manifest・リソース、Gradle、CI・release・Docker設定と参照を確認。旧Compose画面・定数用domain/use caseは削除済み。残る`MainActivity.kt`はHOME判定とOS UIを開くネイティブ境界であり、API 26〜28の分岐も必要なため維持した。
- minSdk 26では旧API向けの白背景は使われないため削除し、実際に使う`drawable-v21/launch_background.xml`の内容を`drawable/launch_background.xml`に統合。使用箇所のないMethodChannel差し替え引数を削除し、既定チャンネルと既存モックを維持した。画面の状態→bool→状態の再変換と、既存規則に含まれるignoreの重複も整理した。
- Kotlinプラグインの`apply false`宣言は未使用ではない。Flutter 3.47.4の`FlutterPluginUtils.detectApplyingKotlinGradlePlugin`が`android.builtInKotlin=false`時に適用するため維持した。互換フラグや署名・リリース保護は変更しない。
- 既存Flutterテスト7件、`flutter analyze`、Dart整形チェック、`git diff --check`が成功。ignore整理後もGradle/buildキャッシュ・local.properties・署名鍵が除外されることを確認。独立した読み取り専用レビューでも削除差分への指摘なし。
- Windows / Flutter 3.47.4で`flutter build apk --debug`が成功。リソース統合後も`android/gradlew.bat lint assembleDebug --console=plain`が成功。Lintはエラー0件、既存Manifestの`DataExtractionRules`・`MissingApplicationIcon`の警告2件。初回Lintが検出したGit管理外`local.properties`のドライブ文字エスケープを修正し、リソース移動後の増分マージ不整合は`:app:mergeDebugResources --rerun-tasks`で再生成した。ログは`build/pr34-android-lint.log`。
- 権限、依存、外部入力、ログ、保存処理の追加なし。秘密情報と残存コードTODOなし。OS UIの端末操作と署名付きReleaseは今回未実施。Android・release用スクリプトに変更はなく、その試験は再実行していない。
- 空の`drawable-v21`フォルダー除去後の最終Lintログは`build/pr34-android-lint-final.log`。上記2件以外のLint警告はない。

2026-09-13、#35（再開時の確認）。
- `refactor/35-flutter-migration` 上で前回の移行差分とdebug APKを確認。検証コンテナ `guri-flutter-build-limited` は終了コード0を保持していた。関連実装に変更がないため、成功済みの試験・解析・ビルドは繰り返していない。
- API 37の専用エミュレーターは前回起動を確認したが、インストール完了とHOME操作の結果は取得できていない。起動途中のインストールは拒否され、起動完了後はストリーミング方式が完了しなかったため通常転送方式を試した。再開時には端末コンテナが停止しており、操作確認は未完了として扱う。API 26の操作確認、署名付きRelease APK、GitHub CIも未確認。
- 開発ルールの整理は `aebbb83` にコミット済み。移行差分の最終確認では `git diff --check` が成功。未確認項目が残るためIssueはopenを維持する。

2026-09-12、#35（Flutter移行の継続検証）。
- 環境: Flutter 3.47.4 / Dart 3.13.3、既存Androidイメージに検証用ツールを追加したDocker環境、JDK 25、Android SDK Platform 36、NDK 28.2。
- `flutter test` は7件成功。Widgetテストで起動時の要求抑止、明示操作、選択後の復帰、外部でHOMEを変更した後の復帰を確認。MethodChannelの未知の応答が失敗状態になることも確認。
- `flutter analyze`、Dart整形、`make android-emulator-test release-test`、YAML構文確認、`git diff --check` が成功。
- `flutter build apk --debug` と `cd android && ./gradlew lint --console=plain` が成功。APKは `build/app/outputs/flutter-apk/app-debug.apk` に生成。
- 初回ビルドはエミュレーターとの同時実行でメモリが逼迫し、SDK導入後に停滞したため停止。エミュレーターを停止して、検証時のみ `GRADLE_OPTS="-Dorg.gradle.jvmargs=-Xmx2g -Dorg.gradle.workers.max=2"` と `JAVA_TOOL_OPTIONS=-XX:ActiveProcessorCount=2` を設定した再実行で成功した。
- Flutterが追加したAGP互換フラグを保持。背景は[FlutterのKotlin移行ガイド](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers)を参照。
- レビューでCI・releaseのGradle wrapper検証が削除されていた点を修正し、再レビューで指摘なし。権限追加、秘密情報、外部入力の保存、ログ出力、コードTODOの追加はない。
- `.codex/DEVELOPMENT.md` の重複手順を整理し、コードはHow、テストはWhat、コミットログはWhy、コードコメントはWhy notという方針を追加。文書レビューと差分確認を実施。
- 署名付きRelease APKとGitHub CIは、この継続検証では未実施。

2026-09-12、#35（Flutter移行）。
- UI、画面状態、HOME設定ユースケースをDartへ移し、Android OS APIだけをMethodChannel先の`MainActivity`へ隔離した。
- `flutter test`（5件）と`flutter analyze`、Android・リリース用script試験が成功した。
- Android SDKがこの作業環境にないため、APK buildと実機上のHOME選択はCIまたはAndroid SDK導入環境で継続確認する。
- 権限追加、秘密情報、外部入力の保存、ログ出力、依存サービスの追加はない。コードTODOも追加していない。

2026-09-12、#35（PR #34 の `e2b783f` に対するローカル整理）。
- アプリ名表示を既存の `app_name` resourceへ統合し、定数用の3クラスと専用テストを削除。HOME処理は変更なし。
- 既存image `guri-launcher-android-emulator:api37` とGradle cacheを使い、ネットワークなしで `./gradlew --offline test lint assembleDebug --console=plain` が成功。HOME関連の単体試験13件、失敗・エラー0件。
- `make android-emulator-test release-test` が成功。起動スクリプトの実行権限もGit indexへ記録。
- 権限・外部入力・ログ・依存関係・ストレージ・署名処理の変更なし。コードTODOの追加なし。
- この記録時点ではFlutter移行と端末上のHOME選択操作は未実施。下記の未確認項目は継続。

2026-09-10、ブランチ `codex-cloud/20-default-home`。
- emulator GUI の起動スクリプトに実行権限がなく、Compose container が `Permission denied` で停止する不具合を修正した。
- Android script の実行権限を自動検査し、同じ退行を検出するようにした。
- この修正は emulator の起動不能を解消するものであり、HOME 選択の端末上での確認結果ではない。下記の未実施項目は引き続き必要。

2026-09-09、ブランチ `feature/20-default-home`。
- 環境: 既存 Docker image `guri-launcher-android-emulator:api37`、JDK 25、compileSdk 35、Gradle 9.7.1。
- コンテナに `make` がないため、同じ Gradle タスクを直接実行する。
- API 26 操作確認: 未実施。利用可能な system image がない。
- API 35 操作確認: 未実施。専用の `guri-launcher-android-emulator:api35` コンテナを `-accel off` で起動したが、668 秒後も `sys.boot_completed` は空、`Service package: not found`。ホストに `/dev/kvm` がない。検証用コンテナは停止した。
- HOME 候補表示・実際の選択/拒否・復帰表示の操作確認が完了するまで Issue #20 は完了扱いにしない。
- 単体試験の platform fake は経路選択と要求制御を検証する。Android adapter の例外捕捉や OS UI の実動作を実機で検証した結果ではない。
- `./gradlew test lint assembleDebug :app:connectedDebugAndroidTest --console=plain`: `BUILD SUCCESSFUL in 35s`。
- 単体試験: 16 件、失敗 0 件、エラー 0 件。API 26/28/29 の経路、選択済み時の要求抑止、要求不能/失敗、選択/拒否、外部 HOME 変更後の復帰表示を検証した。
- Lint と debug APK ビルド: 成功。`RoleManager` の API 29 ガードとヘルパーの `@RequiresApi` を確認した。
- `connectedDebugAndroidTest` タスクは成功したが、接続端末・instrumentation test はなく、端末上の試験実績は 0 件。
- Manifest の HOME/DEFAULT と LAUNCHER の独立 filter、権限追加なし、`git diff --check` を確認した。
- コードレビューで見つかった外部 HOME 変更後の表示不整合を修正し、回帰試験と再レビューで確認した。
