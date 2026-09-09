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
