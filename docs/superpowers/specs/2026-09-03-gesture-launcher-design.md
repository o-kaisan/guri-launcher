# Gesture Launcher Design

## Status

- Date: 2026-09-03
- Status: Approved in conversation; awaiting repository review
- Epic: https://github.com/o-kaisan/guri-launcher/issues/16

## 1. Goal

guri-launcher を Android のホームアプリとして動作させ、次の2種類の連続ジェスチャーで、ユーザーが固定配置したアプリを選択して起動できるようにする。

1. 画面下部の専用ぐりぐりボタンを長押しし、2D スライドで現在のホームページ上のアプリへフォーカスを移動し、指を離して起動する。
2. 設定した画面下コーナーの非表示ポケットからスライドし、1〜4個のアプリを扇状に展開して選択し、指を離して起動する。

操作は短い手数、固定された位置、誤起動しにくい状態遷移を優先する。

## 2. Current State

リポジトリには Kotlin、Jetpack Compose、Gradle Kotlin DSL、JUnit、CI、Android Emulator 実行環境がある。アプリ本体は名称を表示する最小画面であり、HOME intent、アプリ一覧、配置保存、ジェスチャー操作は未実装である。

既存の domain、application、infrastructure、presentation のパッケージ責務を維持し、初期段階では Gradle module を追加しない。

## 3. Scope

### 3.1 MVP

- デフォルト HOME アプリ候補として登録する。
- 現在のユーザープロファイルにある起動可能アプリを取得して起動する。
- アプリを固定グリッドへ割り当て、複数ホームページとして保存する。
- 中央ぐりぐりボタンによる長押しと2Dフォーカス移動を実装する。
- 左右を選べる非表示ポケットと、1〜4個のアプリ割り当てを実装する。
- ポケットから指を離さずアプリを展開、選択、起動する。
- 折りたたみ時と展開時でぐりぐりボタンの位置を切り替える。
- ポインター取消、画面姿勢変更、ページ変更、アプリ削除を安全に処理する。
- Domain unit test、Compose UI test、Android Emulator test を追加する。
- 感度を設定モデルとして保持し、MVP は STANDARD を使用する。

### 3.2 Post-MVP

- LOW、STANDARD、HIGH の3段階をユーザーが設定画面から変更する。
- 3段階の値は本設計で定義した初期値を使用し、実機評価による変更は別 Issue の明示的な仕様変更として扱う。

### 3.3 Non-goals

- Bluetooth、USB キーボード、マウス、トラックパッドからの専用入力
- work profile、private profile、複数ユーザープロファイル
- ウィジェット、フォルダ、検索、通知バッジ
- アプリの自動推薦または配置の自動補完
- アイコンテーマ、自由形状アニメーション、壁紙管理
- QUERY_ALL_PACKAGES 権限

## 4. Terminology

| Term | Meaning |
|---|---|
| Guri control | 画面下部に表示する2D操作開始ボタン |
| Pocket | 待機中は何も表示せず、画面下コーナーの透明領域から開始するクイック起動操作 |
| Current page | ジェスチャー開始時点で表示中のホームページ |
| Focus | 指を離した場合に起動対象となるアプリ |
| Continuous gesture | PointerDown から PointerUp まで同じ指を維持する操作 |
| Gesture tuning | 長押し時間、デッドゾーン、移動ステップ、ポケット展開距離をまとめた設定 |

## 5. Architecture

| Layer | Responsibility |
|---|---|
| domain | アプリ識別子、固定配置、ポケット設定、感度、方向選択、2つのステートマシン |
| application | アプリ一覧取得、配置更新、ページ選択、設定更新、アプリ起動のユースケース |
| infrastructure | LauncherApps、DataStore、WindowManager、Android の触覚・起動結果変換 |
| presentation | Compose 画面、ViewModel、pointer event の変換、フォーカスと扇表示 |

Domain は Android Framework、Compose、DataStore、LauncherApps に依存しない。Presentation と Infrastructure は Application が定義する interface を実装または利用し、Application は Domain を利用する。

2つのジェスチャーは別々のステートマシンを持つ。両方が LaunchRequested を出力し、共通の LaunchApp use case が実際の起動を調整する。

## 6. Domain Model

### 6.1 Application identity

LaunchableAppId は packageName と activityName からなる。MVP は現在のユーザーだけを対象とするため UserHandle は domain model に含めない。

LaunchableApp は次を持つ。

- id: LaunchableAppId
- label: 表示名
- enabled: 起動可能か
- iconKey: Presentation が icon を取得するための opaque key

自分自身の MainActivity は一覧から除外する。

### 6.2 Home layout

HomePageId は安定した文字列 ID とする。GridPosition は row と column の非負整数からなる。同一ページの同一位置には最大1アプリだけを割り当てる。

HomePageLayout は pageId と Map<GridPosition, LaunchableAppId> を持つ。空きマスは Map に含めない。配置編集では同じアプリを同一ページへ重複配置しない。

HomeLayout は順序付きページ一覧と currentPageId を持つ。初回起動時は空のページを1つ作成する。ページは1つ以上を維持する。

### 6.3 Pocket configuration

PocketSide は LEFT または RIGHT である。

PocketConfiguration は次を持つ。

- side: PocketSide
- capacity: 1〜4
- assignments: capacity と同じ長さの順序付き LaunchableAppId 一覧

保存時は全枠の割り当てと重複なしを必須とする。未設定状態は PocketConfiguration が存在しない状態で表す。

設定済みアプリが削除または無効化された場合、識別子と順序を保持し、利用不可として表示する。別アプリで自動置換しない。

### 6.4 Gesture tuning

SensitivityPreset は LOW、STANDARD、HIGH である。

| Preset | Long press | Pre-activation dead zone | Grid step | Pocket activation |
|---|---:|---:|---:|---:|
| LOW | 520ms | 14dp | 52dp | 14dp |
| STANDARD | 420ms | 10dp | 42dp | 10dp |
| HIGH | 320ms | 6dp | 32dp | 6dp |

Fan radius は感度とは独立して100dpとする。MVP は STANDARD を固定利用するが、state machine は GestureTuning を constructor input として受け取る。

### 6.5 Window and control placement

WindowMode は COMPACT または EXPANDED とする。WindowModeProvider は WindowSizeClass、FoldingFeature、window posture の観測結果を Android 固有型から WindowMode へ変換する。

- COMPACT: ぐりぐりボタンを利用可能領域の下部中央へ置く。
- EXPANDED: GuriSideSetting で選んだ左半分または右半分の中央下部へ置く。
- 展開時の初期値は RIGHT とする。
- Pocket の初期 side は LEFT とする。
- hinge、navigation bar、display cutout と重ならないよう WindowInsets を反映する。

WindowMode または利用可能 bounds がジェスチャー中に変化した場合、進行中のジェスチャーをキャンセルする。

## 7. Interfaces

Application が次の interface を定義する。

### AppCatalog

- observeApps(): 起動可能アプリ一覧の stream
- refresh(): 一覧を再取得する
- isAvailable(id): 対象が現在起動可能か確認する

### AppLauncher

- launch(id): LaunchResult を返す
- LaunchResult は Success、Unavailable、Denied、Failed を区別する

### HomeLayoutRepository

- observeLayout(): HomeLayout の stream
- assignApp(pageId, position, appId)
- removeAssignment(pageId, position)
- addPage()
- removePage(pageId)
- selectPage(pageId)

### PocketConfigurationRepository

- observeConfiguration(): 未設定または PocketConfiguration の stream
- saveConfiguration(configuration)
- clearConfiguration()

### LauncherSettingsRepository

- observeSettings(): GuriSideSetting と SensitivityPreset の stream
- setExpandedGuriSide(side)
- setSensitivity(preset)

### WindowModeProvider

- observeWindowMode(): WindowMode と safe bounds の stream

## 8. Guri Control Interaction

### 8.1 States

- Idle
- Pressing
- ActiveWithoutFocus
- ActiveWithFocus

Cancel は永続状態にせず、出力を生成した後に Idle へ戻る。

### 8.2 Start and activation

1. PointerDown がぐりぐりボタン内で発生すると Pressing へ移る。
2. 420ms が経過するまで、PointerDown 位置からの距離が10dp以内なら Pressing を維持する。
3. 420ms 経過時に ActiveWithoutFocus へ移る。開始直後は何もフォーカスしない。
4. 420ms より前に10dpを超えた場合は Idle へ戻り、起動しない。

値は STANDARD の場合であり、将来は選択した GestureTuning を使用する。

### 8.3 Direction extraction

Active 状態の drag delta を x と y の accumulator へ加算する。絶対値が grid step 以上になった軸から1方向イベントを生成する。

両軸がしきい値を超えた場合は、しきい値で正規化した絶対移動量が大きい軸を先に処理する。同値の場合は直前に処理した軸と異なる軸を先にし、初回同値は vertical を先にする。処理した軸から grid step 分を差し引き、残量を保持する。

### 8.4 First focus

最初の方向イベントは、ぐりぐりボタン中心を論理グリッドの直下に投影した anchor から検索する。

候補は指定方向の半平面にあり、現在ページに割り当て済みかつ利用可能なアプリだけとする。候補を次の順で比較する。

1. 方向軸に対する角度のずれが小さい
2. anchor からの距離が短い
3. row、column、LaunchableAppId の辞書順

候補がない場合は ActiveWithoutFocus を維持する。

### 8.5 Subsequent focus movement

現在の GridPosition を基準に同じ directional search を行う。空きマスと利用不可アプリは候補に含めない。候補がない場合は現在の Focus を維持する。

### 8.6 Release and cancellation

- ActiveWithFocus で PointerUp: LaunchRequested を1回だけ出力して Idle へ戻る。
- Pressing または ActiveWithoutFocus で PointerUp: 出力せず Idle へ戻る。
- PointerCancel、2本目の pointer、Activity background、page change、window change: 出力せず Idle へ戻る。

## 9. Invisible Pocket Interaction

### 9.1 Trigger region

Pocket は待機中に icon、button、background、handle を描画しない。

透明な trigger region は設定した側の下コーナーに置く。標準サイズは幅56dp、高さ72dpとし、mandatorySystemGestures を含めず、safeGestures の内側へ配置する。systemGestureExclusion で Android の HOME または BACK gesture を奪わない。

PointerDown が trigger region 内で開始した場合だけ Pocket state machine に入力する。Compose の pointer chain は同じ pointer の後続 event を領域外でも受け取る。

### 9.2 States

- Idle
- Tracking
- ExpandedWithoutSelection
- ExpandedWithSelection

Cancel は出力後に Idle へ戻る。

### 9.3 Expansion

1. PointerDown で Tracking へ移る。この時点では何も描画しない。
2. 設定側コーナーから画面内側かつ上方向への移動が pocket activation 以上になると ExpandedWithoutSelection へ移る。
3. 登録済み1〜4アプリの icon を半径100dpの90度 fan 上に描画する。
4. 展開時に1回だけ触覚フィードバックを返す。

設定が存在しない場合、PointerDown を処理せず Idle を維持する。

### 9.4 Fan geometry

N 個の slot は上方向から画面内側の水平方向までの90度 arc に等間隔で置く。edge 上を避けるため端点は使用せず、各中心角は (index + 1) × 90度 ÷ (N + 1) とする。LEFT と RIGHT は垂直軸で鏡映する。

assignment の index 0 を最も上側へ置き、index が増えるほど画面内側の水平方向へ近づける。

### 9.5 Selection

Pointer の角度が各 slot の中間境界内に入り、起点からの距離が pocket activation 以上なら該当 slot を選択する。選択が変化するたびに触覚フィードバックを1回返す。

起点からの距離が pocket activation 未満へ戻った場合は選択を解除して Tracking へ戻り、icon を非表示にする。利用不可 slot は disabled placeholder として描画し、選択対象にしない。

### 9.6 Release and cancellation

- ExpandedWithSelection で PointerUp: LaunchRequested を1回だけ出力して Idle へ戻る。
- Tracking または ExpandedWithoutSelection で PointerUp: 出力せず Idle へ戻る。
- PointerCancel、2本目の pointer、Activity background、page change、window change: 出力せず Idle へ戻る。
- Tap、2回目の tap、icon への直接 tap は Pocket 起動操作として使用しない。

## 10. Android Integration

### 10.1 HOME registration

MainActivity は次の2 intent filter を別々に持つ。

- ACTION_MAIN と CATEGORY_LAUNCHER
- ACTION_MAIN と CATEGORY_HOME と CATEGORY_DEFAULT

API 29 以上は RoleManager の ROLE_HOME request を使用する。API 26〜28 は system の HOME settings または resolver へ誘導する。device owner API や永続的な preferred activity 設定は使用しない。

### 10.2 App discovery and launch

Infrastructure は LauncherApps.getActivityList(null, currentUser) で一覧を取得し、LauncherApps.startMainActivity で起動する。

- 現在ユーザーだけを対象とする。
- packageName と componentName が一致し、enabled であることを起動直前に再確認する。
- guri-launcher 自身を一覧から除外する。
- label は locale-aware に並べ、同名時は LaunchableAppId で安定化する。
- package change callback と Activity resume の両方で一覧を更新する。
- icon decode と resize は main thread で行わず、memory cache を使用する。
- QUERY_ALL_PACKAGES を要求しない。

### 10.3 Persistence

Infrastructure は immutable な LauncherStoredState を JSON DataStore へ保存する。内容は schemaVersion、HomeLayout、PocketConfiguration、GuriSideSetting、SensitivityPreset である。

Repository は storage DTO と Domain model の変換を担当し、Composable は DataStore を直接参照しない。DataStore instance は application scope で1つだけ生成する。

初期値は次の通り。

- schemaVersion: 1
- HomeLayout: 空ページ1つ
- PocketConfiguration: 未設定
- expanded Guri side: RIGHT
- sensitivity: STANDARD

破損した保存データは CorruptionHandler で初期値へ置換し、設定が初期化されたことを一度だけ画面へ通知する。秘密情報、利用履歴、起動回数は保存しない。

## 11. Presentation Structure

MainActivity は GuriLauncherApp と依存関係の起点だけを担当する。画面と controller を責務ごとに分割する。

- HomeScreen: page、grid、overlay の構成
- HomePager: currentPageId と横 swipe
- AppGrid: 固定 row、column の描画と直接 tap 起動
- GuriControl: 表示、長押し、2D pointer input
- PocketGestureRegion: 非表示 trigger と pointer input
- PocketFanOverlay: icon、focus、disabled placeholder
- LauncherSettingsScreen: アプリ配置、Pocket side、1〜4件、順序、展開時 Guri side
- AppPickerScreen: 起動可能アプリ一覧
- HomeViewModel: layout、current page、launch result
- GestureViewModel: gesture state、focus、cancel
- SettingsViewModel: setting validation と保存

GuriControl と PocketGestureRegion は HomePager の外側に overlay として置く。これにより page が変わっても control の位置を維持する。

いずれかの custom gesture が Active の間は page swipe を無効化する。pageId が外部要因で変わった場合は gesture をキャンセルする。

## 12. Foldable and Resizable Behavior

- COMPACT では GuriControl を safe bounds の下部中央へ置く。
- EXPANDED では setting が LEFT なら左 half の中央下部、RIGHT なら右 half の中央下部へ置く。
- Pocket は端末姿勢に関係なく設定した画面全体の LEFT または RIGHT 下コーナーへ置く。
- Guri と Pocket が同じ side でも、Guri は half 中央、Pocket は corner のため hit region を重ねない。
- hinge が画面を分離する場合は hinge bounds を half の境界として使用する。
- hinge がない expanded window は safe width の中央を境界とする。
- AppGrid の row と column は COMPACT と EXPANDED で維持し、cell size と spacing だけを safe bounds に合わせる。
- configuration change 後も HomeLayout、currentPageId、設定を復元する。

## 13. Error Handling

| Condition | Behavior |
|---|---|
| App removed or disabled | 配置を保持して unavailable 表示。起動しない |
| Launch denied | gesture を Idle に戻し、短い user-facing message を表示 |
| Unexpected launch failure | gesture を Idle に戻し、一般化した message を表示。stack trace を UI に出さない |
| DataStore corruption | 初期値へ復旧し、一度だけ通知 |
| PointerCancel or second pointer | 起動せず Idle |
| Activity background | 起動せず Idle |
| Window or posture change | 起動せず Idle |
| Page change while active | 起動せず Idle |
| No candidate in direction | 現在の focus を維持。初回なら未選択を維持 |
| Pocket assignment unavailable | disabled placeholder。選択と起動を禁止 |

LaunchRequested は gesture ごとに最大1回とし、ViewModel は処理済み event を再実行しない。

## 14. Accessibility and Feedback

- GuriControl は Button role、content description、long-click hint を持つ。
- PocketGestureRegion は視覚的には透明だが、TalkBack 用 semantics と、登録アプリ名を含む custom accessibility actions を持つ。
- Settings から全割り当てを通常の list と button で操作できる。
- icon だけで状態を伝えず、focus outline、scale、label、haptic を組み合わせる。
- system の reduced motion 相当設定が有効な場合、fan と focus animation duration を短縮または無効化する。
- 触覚フィードバックを無効化している端末設定を尊重する。

## 15. Security and Privacy

- Android permission は必要最小限とし、QUERY_ALL_PACKAGES を追加しない。
- Intent と ComponentName は起動直前に LauncherApps で解決し、保存値を無条件に信用しない。
- exported component は HOME と LAUNCHER の entry activity に限定する。
- app list、配置、選択、起動履歴を外部送信しない。
- package name、activity name、個人情報、入力座標を通常ログへ出さない。
- DataStore は app-private storage を使用する。
- 外部 library は AndroidX の必要な artifact に限定し、追加理由を各 Issue と PR に記録する。

## 16. Testing

### 16.1 Domain unit tests

Guri state machine:

- 419ms では有効化せず、420ms で有効化する。
- 長押し前に dead zone を超えると cancel する。
- 開始直後は focus がない。
- first direction から deterministic に候補を選ぶ。
- 空きマスと unavailable app を飛ばす。
- 42dp ごとに1 step 進む。
- diagonal の dominant axis と同値規則を検証する。
- release は focus がある場合だけ1回 LaunchRequested を出す。
- PointerCancel、second pointer、page change、window change で起動しない。

Pocket state machine:

- capacity 1、2、3、4 の fan angle を検証する。
- LEFT と RIGHT が鏡映になる。
- activation 未満では icon を表示しない。
- activation 到達時に fan を表示する。
- drag 中に選択を変更できる。
- origin へ戻ると選択解除する。
- selected release だけが1回 LaunchRequested を出す。
- unavailable slot を選択しない。
- cancel 条件で起動しない。

Settings and layout:

- pocket capacity の1と4を受理し、0と5を拒否する。
- assignment 数不一致と重複を拒否する。
- page は1つ以上を維持する。
- 同一 grid position の重複を拒否する。
- preset から exact tuning values への mapping を検証する。

### 16.2 Application tests

Fake AppCatalog、AppLauncher、Repository、WindowModeProvider を使用する。

- current page の app だけを focus candidates に渡す。
- LaunchRequested を1回だけ AppLauncher へ渡す。
- unavailable result を UI state へ変換する。
- configuration 保存と再読込を検証する。
- package refresh 後も unavailable assignment を保持する。
- window mode change で active gesture を cancel する。

### 16.3 Compose UI tests

performTouchInput と test clock を使用する。

- Guri の long press、drag、focus、release
- Pocket trigger が待機中に視覚表示されない
- Pocket fan が同じ pointer sequence 内で展開する
- 1〜4 icon、左右反転、selection highlight
- selected release で launch callback が1回
- unselected release、cancel、multi-touch で callback が0回
- HomePager の page change と overlay 固定
- COMPACT 下部中央と EXPANDED 左右配置
- TalkBack semantics と custom action

### 16.4 Emulator tests

- guri-launcher を default HOME として選択する。
- 実在する test app を grid と Pocket へ割り当てて起動する。
- gesture navigation と3-button navigation の両方で Pocket が system gesture を妨げない。
- resizable emulator の COMPACT と EXPANDED を切り替える。
- foldable emulator の posture 変更中に active gesture が cancel される。
- app uninstall 後に unavailable 表示となり、別アプリへ置換されない。
- Activity recreation 後に layout と settings が復元される。

## 17. Backlog Decomposition

| Order | Issue | Depends on |
|---:|---|---|
| 1 | Default HOME app registration | Epic #16 |
| 2 | Launchable app catalog and launch adapter | Epic #16 |
| 3 | Fixed grid and app assignment editor | 2 |
| 4 | 2D focus state machine | 3 |
| 5 | Guri control continuous gesture integration | 2, 3, 4 |
| 6 | Pocket side, capacity, ordering, and assignment settings | 2 |
| 7 | Pocket fan state machine | 6 |
| 8 | Invisible Pocket continuous gesture integration | 2, 6, 7 |
| 9 | Fold-aware Guri placement and expanded-side setting | 5 |
| 10 | Multiple pages and current-page focus scope | 3, 5, 8 |
| 11 | Integrated emulator verification | 1 through 10 |
| 12 | Three-level sensitivity setting | 4, 7, 9, 10; Post-MVP |

Each child Issue must describe its independently testable deliverable, Domain/Application interfaces consumed and produced, explicit exclusions, normal/boundary/error tests, security impact, and acceptance criteria. One Pull Request addresses one child Issue.

## 18. Acceptance Criteria

- Android system can select guri-launcher as HOME.
- User can assign launchable apps to fixed grid positions and persist them.
- User can long-press Guri, slide in 2D, release, and launch the focused app.
- Guri begins without an initial focus.
- Only apps on the page current at gesture start are candidates.
- User can configure Pocket LEFT or RIGHT and assign exactly1〜4 unique apps in order.
- Pocket trigger has no visible idle icon, button, handle, or background.
- One continuous Pocket gesture expands icons, changes selection, and launches on release.
- Tap or unselected release does not launch.
- Folded or compact layout places Guri at bottom center.
- Expanded layout places Guri at the selected half bottom center.
- Pocket remains at the configured screen corner across pages.
- System HOME and BACK gestures remain usable.
- All cancel conditions produce no app launch.
- Removed apps remain assigned as unavailable and are never silently replaced.
- Domain, Application, Compose UI, and Emulator verification pass.
- No unnecessary Android permission, secret, personal data log, or unresolved code comment is introduced.

## 19. References

- Android LauncherApps: https://developer.android.com/reference/android/content/pm/LauncherApps
- Android intents and intent filters: https://developer.android.com/guide/components/intents-filters
- Adaptive Compose and foldables: https://developer.android.com/develop/ui/compose/layouts/adaptive/get-started-with-adaptive-apps
- Compose pointer gestures: https://developer.android.com/develop/ui/compose/touch-input/pointer-input/understand-gestures
- Compose WindowInsets: https://developer.android.com/develop/ui/compose/system/insets
- Android DataStore: https://developer.android.com/topic/libraries/architecture/datastore
