# リポジトリの作業ルール

- リポジトリ作業では [トークン効率ルール](.codex/skills/token-efficient-development/SKILL.md) を適用し、調査・ログ・指示の読み込み・検証の重複を抑えます。
- 変更を計画または実装する前に `.codex/DEVELOPMENT.md` を読みます。
- すべての変更を GitHub Issue から開始し、その目的と受入条件を確認します。
- ドメインロジックを Android Framework API から独立させます。
- 振る舞いの変更には単体試験を追加し、利用可能な Test、Lint、Build を実行します。
- 秘密情報をコミットしません。権限、外部入力、ログ、依存関係、ストレージのセキュリティリスクを確認します。
- 後続対応の TODO は `TODO(#<Issue番号>): <何を、なぜ>` と記載し、対応する Issue を作成します。
- Pull Request には関連 Issue、設計判断、試験、セキュリティ確認、残存 TODO、検証結果を記載します。
