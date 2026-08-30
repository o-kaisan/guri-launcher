# guri-launcher

Android 向けランチャーアプリの開発基盤です。現在は Kotlin と Jetpack Compose で、アプリ名を表示する最小構成を提供しています。

## 必要な環境

- JDK 17
- Android Studio（または Android SDK。API 35）

## ローカルでの確認

Android Studio でリポジトリのルートを開くか、SDK の場所を `local.properties` の `sdk.dir` または `ANDROID_HOME` に設定して実行します。

```shell
./gradlew test
./gradlew lint
./gradlew assembleDebug
```

Debug APK は `app/build/outputs/apk/debug/app-debug.apk` に生成されます。Pull Request と `main` への push では同じ確認を CI で実行します。`vX.Y.Z` タグでは、バージョンを含む名前の APK と自動生成したリリースノートを GitHub Release へ公開します。

## 開発への参加

設計、実装、テスト、セキュリティ確認、Pull Request の進め方は [開発ルール](.codex/DEVELOPMENT.md) を参照してください。
