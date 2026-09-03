# Gesture Launcher MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** guri-launcher を Android の HOME アプリとして動作させ、画面サイズへ適応する相対配置グリッド、中央のぐりぐり操作、左右どちらかの非表示 Pocket 操作からアプリを1回だけ安全に起動できるようにする。

**Architecture:** Android 型を含まない Domain に、相対 GridAnchor、safe viewportから行列数を算出する pure calculator、anchorを実セルへ割り当てる resolver、2つのgesture state machineを置く。Application がアプリ一覧・起動・配置・overflow reflow・設定・window状態のport/use caseを定義し、Infrastructureが `LauncherApps`、JSON DataStore、WindowManagerで実装する。PresentationはComposeのviewport/pointer eventをDomain inputへ変換し、解決済みセルと一回限りの起動effectを描画・実行する。

**Tech Stack:** Kotlin 2.4.10、Android Gradle Plugin 9.3.2、Jetpack Compose（既存 BOM 2025.01.01）、Lifecycle 2.11.0、DataStore 1.2.1、WindowManager 1.5.1、kotlinx.coroutines 1.10.2、kotlinx.serialization JSON 1.11.0、JUnit 4.13.2、AndroidX Test Runner 1.7.0、AndroidX Test ext.junit 1.3.0、Espresso 3.7.0。

**Spec:** [`docs/superpowers/specs/2026-09-03-gesture-launcher-design.md`](../specs/2026-09-03-gesture-launcher-design.md)

## Global Constraints

- [ ] 1 Issue = 1 PR とし、各PRの本文に `Closes #<issue>` を記載する。
- [ ] Domain と Application の production code から `android.*`、`androidx.*`、Compose、DataStore、`LauncherApps` を参照しない。
- [ ] 現在のユーザープロファイルだけを対象にし、自アプリを一覧から除外する。
- [ ] `QUERY_ALL_PACKAGES`、利用履歴、起動回数、アプリ選択ログを追加しない。
- [ ] PointerCancel、2本目の pointer、background、page change、window change では起動しない。
- [ ] 削除・無効化された割り当ては識別子と相対位置を保持し、自動置換しない。
- [ ] GridAnchorは各軸0〜1000、target cellは88dp×104dp、columns上限6、rows上限7とする。
- [ ] window変更時はgestureを先にcancelし、overflowは後続pageへ送る。拡大時に前pageへ自動回収しない。
- [ ] 各PRで `./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug` を実行し、UI変更PRでは `./gradlew :app:connectedDebugAndroidTest` も実行する。
- [ ] 実装中に未完箇所を残す場合はリポジトリ規約の `TODO(#Issue): ...` 形式だけを使う。

## Delivery Order

| Wave | Backlog item | Depends on |
|---|---|---|
| A | 1. Default HOME registration | Epic |
| A | 2. App catalog and launcher | Epic |
| B | 3. Responsive grid and relative-position assignment editor | 2 |
| B | 6. Pocket configuration | 2 |
| C | 4. Guri focus state machine | 3 |
| C | 7. Pocket fan state machine | 6 |
| D | 5. Guri gesture UI integration | 2, 3, 4 |
| D | 8. Invisible Pocket UI integration | 2, 6, 7 |
| E | 9. Fold-aware Guri placement | 5 |
| E | 10. Multiple pages | 3, 5, 8 |
| F | 11. Integrated emulator verification | 1–10 |
| Post-MVP | 12. Three-level sensitivity | 4, 7, 9, 10 |

Wave 内の項目は独立しているため並行実装できる。次の Wave は依存PRが `main` にマージされてから開始する。

## File Map

### Existing files to modify

- `gradle/libs.versions.toml`: AndroidX、DataStore、WindowManager、coroutines、serialization、テスト依存の version catalog。
- `app/build.gradle.kts`: serialization plugin、依存関係、instrumentation runner。
- `app/src/main/AndroidManifest.xml`: HOME/LAUNCHER intent filter と最小 package visibility。
- `app/src/main/java/io/github/okaisan/gurilauncher/infrastructure/AndroidAppContainer.kt`: Android composition root。
- `app/src/main/java/io/github/okaisan/gurilauncher/presentation/MainActivity.kt`: HOME、設定、picker の画面入口と lifecycle event。

### New production packages

- `domain/app`: `LaunchableAppId`、`LaunchableApp`、`LaunchResult`。
- `domain/layout`: `GridAnchor`、`GridViewport`、`ResponsiveGridMetrics`、`ResolvedGridPosition`、`ResponsiveGridCalculator`、`ResponsiveGridResolver`、`HomePlacement`、`HomePageId`、`HomePageLayout`、`HomeLayout`。
- `domain/gesture`: 座標、感度、共通出力、方向 resolver、Guri state machine。
- `domain/pocket`: Pocket 設定、fan geometry、Pocket state machine。
- `domain/window`: Window mode、Guri side、safe bounds。
- `application/app`: app catalog、launcher port、一覧監視、起動 use case。
- `application/layout`: layout repository、相対配置、overflow reflow、page use case。
- `application/pocket`: Pocket repository と更新 use case。
- `application/settings`: launcher settings repository と更新 use case。
- `application/window`: window snapshot provider。
- `infrastructure/app`: `LauncherApps` catalog、launcher、icon loader。
- `infrastructure/storage`: JSON DataStore DTO、serializer、各 repository adapter。
- `infrastructure/window`: WindowManager adapter。
- `presentation/home`: home UI state、ViewModel、pager、grid。
- `presentation/gesture`: gesture ViewModel、Guri control、Pocket region、fan overlay。
- `presentation/settings`: settings ViewModel、settings screen、app picker。

### Test layout

- `app/src/test/java/io/github/okaisan/gurilauncher/domain/**`: Android 非依存の不変条件と状態遷移。
- `app/src/test/java/io/github/okaisan/gurilauncher/application/**`: fake port を使う use case test。
- `app/src/test/java/io/github/okaisan/gurilauncher/infrastructure/storage/**`: DTO mapping と corruption fallback。
- `app/src/androidTest/java/io/github/okaisan/gurilauncher/presentation/**`: Compose pointer sequence と UI semantics。
- `docs/testing/gesture-launcher-emulator-matrix.md`: 実機能の emulator 検証記録。

## Task 1: Register as an Android HOME App

**Backlog:** `[MVP] デフォルトHOMEアプリとして起動できるようにする`

**Files:**

- Modify: `app/src/main/AndroidManifest.xml`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/infrastructure/home/HomeRoleRequester.kt`
- Create: `app/src/test/java/io/github/okaisan/gurilauncher/infrastructure/home/HomeRoleDecisionTest.kt`
- Modify: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/MainActivity.kt`

**Consumes:** Android `RoleManager` on API 29+ and the system HOME resolver on API 26–28.

**Produces:** `HomeRoleRequester.request(activity): HomeRoleRequestResult`; no Domain dependency.

- [ ] **Step 1: Write the API-level decision test.**

```kotlin
@Test fun `API 29 uses role manager`() {
    assertEquals(HomeRoleRoute.ROLE_MANAGER, decideHomeRoleRoute(29))
}

@Test fun `API 28 uses home settings`() {
    assertEquals(HomeRoleRoute.HOME_SETTINGS, decideHomeRoleRoute(28))
}
```

- [ ] **Step 2: Run the focused test and confirm it fails because the decision API does not exist.**

Run: `./gradlew :app:testDebugUnitTest --tests '*HomeRoleDecisionTest'`

- [ ] **Step 3: Add separate LAUNCHER and HOME intent filters.**

```xml
<intent-filter>
    <action android:name="android.intent.action.MAIN" />
    <category android:name="android.intent.category.HOME" />
    <category android:name="android.intent.category.DEFAULT" />
</intent-filter>
<intent-filter>
    <action android:name="android.intent.action.MAIN" />
    <category android:name="android.intent.category.LAUNCHER" />
</intent-filter>
```

- [ ] **Step 4: Implement `HomeRoleRoute`, the pure decision function, and `HomeRoleRequester`.** Return `AlreadyHome`, `RequestStarted`, or `SettingsOpened`; never swallow `ActivityNotFoundException`.
- [ ] **Step 5: Add a settings action in `MainActivity` that calls the requester only after explicit user input.** Do not prompt every time HOME opens.
- [ ] **Step 6: Run focused and full unit tests, then lint and assemble.**

Run: `./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug`

- [ ] **Step 7: Commit.**

```bash
git add app/src/main/AndroidManifest.xml app/src/main/java app/src/test/java
git commit -m "feat: register guri-launcher as a home app"
```

## Task 2: Add the Launchable App Catalog and Launch Use Case

**Backlog:** `[MVP] 起動可能アプリの取得・起動基盤を実装する`

**Files:**

- Modify: `gradle/libs.versions.toml`
- Modify: `app/build.gradle.kts`
- Modify: `app/src/main/AndroidManifest.xml`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/app/LaunchableAppId.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/app/LaunchableApp.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/app/LaunchResult.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/app/AppCatalog.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/app/AppLauncher.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/app/ObserveLaunchableApps.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/app/LaunchApp.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/infrastructure/app/AndroidLauncherAppsCatalog.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/infrastructure/app/AndroidAppLauncher.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/infrastructure/app/AppIconLoader.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/infrastructure/storage/LauncherStoredState.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/infrastructure/storage/LauncherStoredStateSerializer.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/infrastructure/storage/LauncherStateStore.kt`
- Modify: `app/src/main/java/io/github/okaisan/gurilauncher/infrastructure/AndroidAppContainer.kt`
- Test: `app/src/test/java/io/github/okaisan/gurilauncher/domain/app/LaunchableAppIdTest.kt`
- Test: `app/src/test/java/io/github/okaisan/gurilauncher/application/app/LaunchAppTest.kt`

**Consumes:** `LauncherApps.getActivityList()` and `LauncherApps.startMainActivity()` for `Process.myUserHandle()`.

**Produces:**

```kotlin
data class LaunchableAppId(val packageName: String, val className: String) {
    val stableKey: String get() = "$packageName/$className"
}

data class LaunchableApp(
    val id: LaunchableAppId,
    val label: String,
    val isAvailable: Boolean,
)

interface AppCatalog {
    fun observeApps(): Flow<List<LaunchableApp>>
    suspend fun refresh()
}

interface AppLauncher {
    suspend fun launch(id: LaunchableAppId): LaunchResult
}
```

- [ ] **Step 1: Add stable dependency aliases.** Add Lifecycle `2.11.0`, coroutines `1.10.2`, serialization JSON `1.11.0`, DataStore `1.2.1`, WindowManager `1.5.1`, AndroidX Test runner `1.7.0`, ext.junit `1.3.0`, Espresso `3.7.0`, and Compose UI test modules. Apply `org.jetbrains.kotlin.plugin.serialization` with Kotlin `2.4.10`; set `testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"`.
- [ ] **Step 2: Add the minimal launcher visibility query.**

```xml
<queries>
    <intent>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
    </intent>
</queries>
```

- [ ] **Step 3: Write failing value-object and use-case tests.**

```kotlin
@Test(expected = IllegalArgumentException::class)
fun `blank package is rejected`() { LaunchableAppId("", "MainActivity") }

@Test fun `launch delegates once and returns its result`() = runTest {
    val fake = RecordingAppLauncher(LaunchResult.Started)
    assertEquals(LaunchResult.Started, LaunchApp(fake)(APP_ID))
    assertEquals(listOf(APP_ID), fake.calls)
}
```

- [ ] **Step 4: Run focused tests and confirm they fail.**

Run: `./gradlew :app:testDebugUnitTest --tests '*LaunchableAppIdTest' --tests '*LaunchAppTest'`

- [ ] **Step 5: Implement Domain values and Application ports/use cases.** `LaunchResult` has `Started`, `Unavailable`, and `Failed(LaunchFailureReason)`; reasons are stable enums and contain no exception text.
- [ ] **Step 6: Implement `AndroidLauncherAppsCatalog`.** Sort by locale-aware label then `stableKey`, exclude `applicationId`, use the current `UserHandle`, refresh on package add/change/remove callbacks and Activity resume, and perform label/icon loading off main.
- [ ] **Step 7: Implement `AndroidAppLauncher`.** Resolve the exact component immediately before launch; map missing/disabled components to `Unavailable`; map `SecurityException` and runtime start failure to non-sensitive failure enums.
- [ ] **Step 8: Establish the shared storage foundation required by the independent layout, Pocket, and window-setting PRs.** Create one application-scoped `LauncherStateStore` around `DataStore<LauncherStoredState>`. The schema-1 DTO contains an empty one-page home value, nullable Pocket value, `expandedGuriSide = "RIGHT"`, and `sensitivityPreset = "STANDARD"`; its serializer replaces corrupt data with that exact default. Domain mapping remains in later repository adapters.
- [ ] **Step 9: Wire one application-scoped catalog, launcher, and state store into `AndroidAppContainer`.**
- [ ] **Step 10: Run tests, lint, and assemble.**

Run: `./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug`

- [ ] **Step 11: Commit.**

```bash
git add gradle/libs.versions.toml app/build.gradle.kts app/src
git commit -m "feat: add launchable app catalog and launcher"
```

## Task 3: Persist a Responsive Grid and Add Assignment Editing

**Backlog:** `[MVP] レスポンシブグリッドとアプリ配置編集を実装する`

**Files:**

- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/layout/GridAnchor.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/layout/GridViewport.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/layout/ResponsiveGridMetrics.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/layout/ResolvedGridPosition.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/layout/ResponsiveGridCalculator.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/layout/ResponsiveGridResolver.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/layout/HomePlacement.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/layout/HomePageId.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/layout/HomePageLayout.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/layout/HomeLayout.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/layout/HomeLayoutRepository.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/layout/ObserveHomeLayout.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/layout/AssignAppToGrid.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/infrastructure/storage/DataStoreHomeLayoutRepository.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/home/AppGrid.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/settings/AppPickerScreen.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/settings/LauncherSettingsScreen.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/settings/SettingsViewModel.kt`
- Test: matching `domain/layout`, `application/layout`, `infrastructure/storage`, and Compose test files.

**Interfaces:**

- Consumes: `AppCatalog.observeApps(): Flow<List<LaunchableApp>>` and Task 2's application-scoped `LauncherStateStore`.
- Produces:

```kotlin
@JvmInline
value class RelativeCoordinate(val permille: Int)

data class GridAnchor(
    val horizontal: RelativeCoordinate,
    val vertical: RelativeCoordinate,
)

data class GridViewport(val widthDp: Float, val heightDp: Float)
data class ResponsiveGridMetrics(val columns: Int, val rows: Int) {
    val capacity: Int get() = columns * rows
}
data class ResolvedGridPosition(val row: Int, val column: Int)
data class HomePlacement(val appId: LaunchableAppId, val anchor: GridAnchor)
data class ResolvedGrid(
    val placements: Map<ResolvedGridPosition, HomePlacement>,
    val overflow: List<HomePlacement>,
)

class ResponsiveGridCalculator {
    fun calculate(viewport: GridViewport): ResponsiveGridMetrics
}

class ResponsiveGridResolver {
    fun resolve(
        metrics: ResponsiveGridMetrics,
        placements: List<HomePlacement>,
    ): ResolvedGrid
}
```

- [ ] **Step 1: Write failing coordinate and sizing tests.**

```kotlin
@Test fun `responsive boundaries are exact`() {
    val calculator = ResponsiveGridCalculator()
    assertEquals(3, calculator.calculate(GridViewport(351f, 519f)).columns)
    assertEquals(4, calculator.calculate(GridViewport(352f, 519f)).columns)
    assertEquals(4, calculator.calculate(GridViewport(352f, 519f)).rows)
    assertEquals(5, calculator.calculate(GridViewport(352f, 520f)).rows)
    assertEquals(6, calculator.calculate(GridViewport(2_000f, 2_000f)).columns)
    assertEquals(7, calculator.calculate(GridViewport(2_000f, 2_000f)).rows)
}

@Test(expected = IllegalArgumentException::class)
fun `relative coordinate rejects 1001`() {
    RelativeCoordinate(1001)
}
```

- [ ] **Step 2: Run the sizing tests and confirm missing types fail.**

Run: `./gradlew :app:testDebugUnitTest --tests '*ResponsiveGridCalculatorTest' --tests '*GridAnchorTest'`

Expected: FAIL because the responsive grid types do not exist.

- [ ] **Step 3: Implement the exact calculator.**

```kotlin
class ResponsiveGridCalculator {
    fun calculate(viewport: GridViewport): ResponsiveGridMetrics {
        require(viewport.widthDp > 0f && viewport.heightDp > 0f)
        return ResponsiveGridMetrics(
            columns = floor(viewport.widthDp / 88f).toInt().coerceIn(1, 6),
            rows = floor(viewport.heightDp / 104f).toInt().coerceIn(1, 7),
        )
    }
}
```

- [ ] **Step 4: Run the focused tests and confirm they pass.**

Run: `./gradlew :app:testDebugUnitTest --tests '*ResponsiveGridCalculatorTest' --tests '*GridAnchorTest'`

Expected: PASS.

- [ ] **Step 5: Write failing relative-position, collision, and overflow tests.**

```kotlin
@Test fun `top right anchor stays top right when dimensions change`() {
    val placement = HomePlacement(APP_ID, GridAnchor(relative(1000), relative(0)))
    val compact = resolver.resolve(ResponsiveGridMetrics(4, 5), listOf(placement))
    val expanded = resolver.resolve(ResponsiveGridMetrics(6, 7), listOf(placement))
    assertEquals(ResolvedGridPosition(0, 3), compact.positionOf(APP_ID))
    assertEquals(ResolvedGridPosition(0, 5), expanded.positionOf(APP_ID))
}

@Test fun `overflow is stable and never hidden`() {
    val result = resolver.resolve(
        ResponsiveGridMetrics(columns = 1, rows = 1),
        listOf(topLeft(APP_A), bottomRight(APP_B)),
    )
    assertEquals(setOf(APP_A), result.placements.values.map { it.appId }.toSet())
    assertEquals(listOf(APP_B), result.overflow.map { it.appId })
}
```

- [ ] **Step 6: Run the resolver tests and confirm missing behavior fails.**

Run: `./gradlew :app:testDebugUnitTest --tests '*ResponsiveGridResolverTest'`

Expected: FAIL because `resolve` is not implemented.

- [ ] **Step 7: Implement deterministic resolution.** Sort placements by vertical permille, horizontal permille, and `appId.stableKey`. For each placement, choose the empty cell with minimum squared normalized-center distance; break equal distance by row then column. Return unassigned placements as `overflow` in the same stable order.

- [ ] **Step 8: Run resolver and layout invariant tests.**

Run: `./gradlew :app:testDebugUnitTest --tests '*ResponsiveGridResolverTest' --tests '*HomePageLayoutTest'`

Expected: PASS for relative remapping, collision tie-break, duplicate app/anchor rejection, and stable overflow.

- [ ] **Step 9: Implement persistence and assignment.** Store `horizontalPermille` and `verticalPermille` in schema 1. `AssignAppToGrid` receives the selected cell plus current metrics, converts the cell center with `round((index + 0.5) / count * 1000)`, moves an existing app ID, and atomically saves its new anchor.

- [ ] **Step 10: Add responsive `AppGrid` and editor UI.** Measure only the viewport remaining after safe drawing insets and the Guri reserved region. Render `metrics.columns × metrics.rows`, distribute remaining width/height evenly, expose occupied and empty-cell semantics, and render unavailable placements without changing their anchor.

- [ ] **Step 11: Add Compose tests for at least 320×568dp, 360×800dp, and 673×841dp viewports.** Assert calculated dimensions, top-right/center relative placement, direct-tap launch, empty-cell edit action, and no clipped cell.

- [ ] **Step 12: Run unit, UI, lint, and build verification.**

Run: `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleDebug`

Expected: all tasks succeed.

- [ ] **Step 13: Commit.**

```bash
git add app/src
git commit -m "feat: add responsive home grid assignment"
```

## Task 4: Implement the Pure Guri Focus State Machine

**Backlog:** `[MVP] 2Dフォーカス移動ステートマシンを実装する`

**Files:**

- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/gesture/Geometry.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/gesture/GestureTuning.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/gesture/GestureOutput.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/gesture/Direction.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/gesture/DirectionalFocusResolver.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/gesture/GuriGestureStateMachine.kt`
- Tests: `DirectionalFocusResolverTest.kt`, `GuriGestureStateMachineTest.kt`.

**Consumes:** immutable current-page `FocusCandidate` values and a `GestureTuning` constructor argument.

**Produces:**

```kotlin
data class GestureTuning(
    val longPressMillis: Long,
    val preActivationDeadZoneDp: Float,
    val gridStepDp: Float,
    val pocketActivationDp: Float,
)

sealed interface GuriEvent {
    data class Down(val pointerId: Long) : GuriEvent
    data class PreActivationMove(val pointerId: Long, val total: VectorDp) : GuriEvent
    data class LongPressElapsed(val pointerId: Long) : GuriEvent
    data class DragBy(val pointerId: Long, val delta: VectorDp) : GuriEvent
    data class Up(val pointerId: Long) : GuriEvent
    data object SecondPointer : GuriEvent
    data object Cancel : GuriEvent
    data object ContextChanged : GuriEvent
}

sealed interface GestureOutput {
    data class FocusChanged(val appId: LaunchableAppId?) : GestureOutput
    data class LaunchRequested(val appId: LaunchableAppId) : GestureOutput
    data object Activated : GestureOutput
    data object Cancelled : GestureOutput
}
```

- [ ] **Step 1: Write exact-threshold failing tests.** Verify 419ms is still pressing, `LongPressElapsed` at 420ms activates, moving beyond 10dp first cancels, and activation starts with no focus.
- [ ] **Step 2: Write resolver tests from the spec.** Build candidates from Task 3's `ResolvedGridPosition`; verify half-plane filtering, angle, distance, resolved row/column/AppId tie-break, unavailable exclusion, current-page-only candidates, and cancellation before a viewport-driven re-resolution.
- [ ] **Step 3: Write accumulator tests.** At STANDARD, 41dp emits no direction, 42dp emits one, 84dp emits two; diagonal ordering uses normalized magnitude, alternating axis on ties, and vertical first on the first tie.
- [ ] **Step 4: Write release/cancel tests.** Focused `Up` emits exactly one `LaunchRequested`; unfocused `Up`, second pointer, cancel, and context change emit none and return to Idle.
- [ ] **Step 5: Run focused tests and confirm all new tests fail.**

Run: `./gradlew :app:testDebugUnitTest --tests '*DirectionalFocusResolverTest' --tests '*GuriGestureStateMachineTest'`

- [ ] **Step 6: Implement resolver and state machine without clock, coroutine, Android, or Compose dependencies.** The caller owns the 420ms timer and sends `LongPressElapsed`.
- [ ] **Step 7: Run focused and full tests.**

Run: `./gradlew :app:testDebugUnitTest :app:lintDebug`

- [ ] **Step 8: Commit.**

```bash
git add app/src/main/java/io/github/okaisan/gurilauncher/domain/gesture app/src/test
git commit -m "feat: add guri focus state machine"
```

## Task 5: Integrate the Guri Continuous Gesture in Compose

**Backlog:** `[MVP] 中央ぐりぐりボタンの連続スライド選択を実装する`

**Files:**

- Create: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/gesture/GestureViewModel.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/gesture/GuriControl.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/home/HomeUiState.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/home/HomeViewModel.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/home/HomeScreen.kt`
- Modify: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/MainActivity.kt`
- Tests: `GuriControlTest.kt`, `GestureViewModelTest.kt`, `HomeViewModelTest.kt`.

**Consumes:** Task 2 `LaunchApp`, Task 3 current page, Task 4 state machine.

**Produces:** one continuous `Down → hold → drag → Up` flow and a consumed-once launch effect.

- [ ] **Step 1: Write ViewModel tests with a fake launcher.** Send a state-machine `LaunchRequested` twice with the same effect ID and verify the application use case is invoked once.
- [ ] **Step 2: Write Compose tests.** Use `performTouchInput`, keep the same pointer down for 420ms, drag 42dp toward an assigned cell, release, and assert one launch callback; test 419ms, no direction, PointerCancel, and two-pointer paths with zero callbacks.
- [ ] **Step 3: Run the tests and confirm failure.**

Run: `./gradlew :app:testDebugUnitTest --tests '*GestureViewModelTest' --tests '*HomeViewModelTest' && ./gradlew :app:connectedDebugAndroidTest`

- [ ] **Step 4: Implement `GestureViewModel`.** Snapshot `currentPageId` and candidates on Down; route state-machine outputs to `StateFlow<GestureUiState>` and an ID-bearing channel consumed exactly once; cancel on `onStop`, catalog invalidation, and explicit context change.
- [ ] **Step 5: Implement `GuriControl`.** Use one `pointerInput` handler, `awaitEachGesture`, a 420ms child timer, density conversion at the boundary, Button role, long-click hint, focus haptic, and an obvious focus outline/label.
- [ ] **Step 6: Compose `HomeScreen`.** Place `GuriControl` as an overlay outside grid content at the compact bottom center; keep app direct-tap launching available.
- [ ] **Step 7: Wire lifecycle cancellation from `MainActivity`.** `ON_STOP` sends cancel before the Activity loses foreground.
- [ ] **Step 8: Run unit, UI, lint, and build verification.**

Run: `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleDebug`

- [ ] **Step 9: Commit.**

```bash
git add app/src
git commit -m "feat: add continuous guri gesture"
```

## Task 6: Persist Pocket Side, Capacity, Order, and Assignments

**Backlog:** `[MVP] ポケットの左右・アプリ数・割り当て設定を実装する`

**Files:**

- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/pocket/PocketSide.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/pocket/PocketConfiguration.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/pocket/PocketConfigurationRepository.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/pocket/UpdatePocketConfiguration.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/infrastructure/storage/DataStorePocketConfigurationRepository.kt`
- Modify: `app/src/main/java/io/github/okaisan/gurilauncher/infrastructure/storage/LauncherStoredState.kt`
- Modify: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/settings/LauncherSettingsScreen.kt`
- Modify: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/settings/SettingsViewModel.kt`
- Tests: `PocketConfigurationTest.kt`, `UpdatePocketConfigurationTest.kt`, repository mapping test.

**Consumes:** Task 2 app list and shared `LauncherStateStore`; this task does not depend on Task 3.

**Produces:** nullable `PocketConfiguration`; configured values contain 1–4 unique IDs and `assignments.size == capacity`.

- [ ] **Step 1: Write failing invariant tests for capacities 0, 1, 4, 5, size mismatch, duplicate IDs, LEFT, RIGHT, and unset configuration.**
- [ ] **Step 2: Run and confirm failure.**

Run: `./gradlew :app:testDebugUnitTest --tests '*PocketConfigurationTest' --tests '*UpdatePocketConfigurationTest'`

- [ ] **Step 3: Implement immutable Domain values and an atomic update use case.** Return typed validation errors instead of partially saving a draft.
- [ ] **Step 4: Implement Pocket DTO mapping over the schema-1 nullable Pocket fields created in Task 2.** Existing home fields remain byte-for-byte equivalent after a Pocket-only update. A new draft starts with side LEFT and capacity 4; the persisted value remains null until all four slots are valid or the user explicitly chooses another capacity and fills every slot.
- [ ] **Step 5: Implement settings UI.** Add LEFT/RIGHT segmented choice, capacity choices 1–4, ordered slots, picker, reorder, remove, save, clear, and disabled unavailable rows that retain their IDs.
- [ ] **Step 6: Add repository round-trip and process recreation UI tests.**
- [ ] **Step 7: Run unit, UI, lint, and build verification.**

Run: `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleDebug`

- [ ] **Step 8: Commit.**

```bash
git add app/src
git commit -m "feat: add pocket configuration"
```

## Task 7: Implement the Pure Pocket Fan State Machine

**Backlog:** `[MVP] ポケットのファン選択ステートマシンを実装する`

**Files:**

- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/pocket/PocketFanGeometry.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/pocket/PocketGestureStateMachine.kt`
- Tests: `PocketFanGeometryTest.kt`, `PocketGestureStateMachineTest.kt`.

**Consumes:** Task 6 Pocket configuration and `GestureTuning.pocketActivationDp`.

**Produces:** deterministic 90-degree mirrored fan positions at radius 100dp and Pocket gesture outputs.

```kotlin
sealed interface PocketEvent {
    data class Down(val pointerId: Long, val origin: PointDp) : PocketEvent
    data class MoveTo(val pointerId: Long, val point: PointDp) : PocketEvent
    data class Up(val pointerId: Long) : PocketEvent
    data object SecondPointer : PocketEvent
    data object Cancel : PocketEvent
    data object ContextChanged : PocketEvent
}
```

- [ ] **Step 1: Write geometry tests.** For capacity `N`, assert slot-center angles `(index + 1) * 90 / (N + 1)`, radius 100dp, assignment order from top toward horizontal, and exact LEFT/RIGHT mirroring for N=1..4.
- [ ] **Step 2: Write state tests.** Under 10dp remains Tracking with no visible output; crossing 10dp emits fan display; movement chooses nearest eligible slot; unavailable slots never select; selected Up emits one launch; tap, unselected Up, second pointer, cancel, and context change emit none.
- [ ] **Step 3: Run and confirm tests fail.**

Run: `./gradlew :app:testDebugUnitTest --tests '*PocketFanGeometryTest' --tests '*PocketGestureStateMachineTest'`

- [ ] **Step 4: Implement the pure geometry and state machine.** Use squared distances for selection; reject pointer ID changes; return Idle after every terminal event.
- [ ] **Step 5: Run focused and full unit tests.**

Run: `./gradlew :app:testDebugUnitTest :app:lintDebug`

- [ ] **Step 6: Commit.**

```bash
git add app/src/main/java/io/github/okaisan/gurilauncher/domain/pocket app/src/test
git commit -m "feat: add pocket fan state machine"
```

## Task 8: Integrate the Invisible Pocket Continuous Gesture

**Backlog:** `[MVP] 非表示ポケットの連続スライド起動を実装する`

**Files:**

- Create: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/gesture/PocketGestureRegion.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/gesture/PocketFanOverlay.kt`
- Modify: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/gesture/GestureViewModel.kt`
- Modify: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/home/HomeScreen.kt`
- Tests: `PocketGestureRegionTest.kt`, `PocketFanOverlayTest.kt`, `PocketGestureViewModelTest.kt`.

**Consumes:** Task 2 `LaunchApp`, Task 6 configuration, Task 7 state machine.

**Produces:** idle-transparent 56dp × 72dp safe-gesture trigger and continuous fan selection.

- [ ] **Step 1: Write Compose tests asserting no idle icon, button, background, or handle is drawn.** The region still exposes a TalkBack label and custom actions for assigned apps.
- [ ] **Step 2: Write one-pointer gesture tests.** Start inside the configured corner, move beyond the original bounds and 10dp activation, verify 1–4 icons, select, release, and assert one launch callback.
- [ ] **Step 3: Add failure-path tests.** Pointer down outside the region, tap, unselected release, direct icon tap, PointerCancel, and second pointer each launch zero apps.
- [ ] **Step 4: Run UI tests and confirm failure.**

Run: `./gradlew :app:connectedDebugAndroidTest`

- [ ] **Step 5: Implement `PocketGestureRegion`.** Place it inside `WindowInsets.safeGestures`, excluding `mandatorySystemGestures`; do not call `systemGestureExclusion`; retain the original pointer chain after leaving bounds.
- [ ] **Step 6: Implement `PocketFanOverlay`.** Draw labels, focus outline/scale, disabled placeholders, optional haptic, and reduced-motion-safe transitions. Icons appear only after the state machine expands.
- [ ] **Step 7: Route Pocket launch effects through the same consumed-once `LaunchApp` path as Guri.**
- [ ] **Step 8: Run unit, UI, lint, and build verification.**

Run: `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleDebug`

- [ ] **Step 9: Commit.**

```bash
git add app/src
git commit -m "feat: add invisible pocket gesture"
```

## Task 9: Place Guri Correctly on Compact and Expanded Windows

**Backlog:** `[MVP] 折りたたみ状態に応じてぐりぐりボタンを配置する`

**Files:**

- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/window/WindowMode.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/window/GuriSideSetting.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/window/SafeBounds.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/window/WindowModeProvider.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/infrastructure/window/AndroidWindowModeProvider.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/settings/LauncherSettings.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/settings/LauncherSettingsRepository.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/infrastructure/storage/DataStoreLauncherSettingsRepository.kt`
- Modify: `LauncherStoredState.kt`, `HomeScreen.kt`, `AppGrid.kt`, `LauncherSettingsScreen.kt`, `GestureViewModel.kt`.
- Tests: `GuriPlacementTest.kt`, `AndroidWindowModeMappingTest.kt`, Compose placement tests.

**Consumes:** WindowManager `WindowInfoTracker`, window metrics, density, safe insets, and Task 5 Guri control.

**Produces:** `Flow<WindowSnapshot>` with COMPACT/EXPANDED, safe bounds, optional separating hinge, deterministic Guri center, and the safe grid viewport consumed by Task 3's `ResponsiveGridCalculator`.

- [ ] **Step 1: Write pure placement tests.** Compact always yields safe-bounds bottom center; expanded LEFT/RIGHT yields selected half bottom center; a separating hinge defines the boundary; without hinge the safe-width midpoint does.
- [ ] **Step 2: Write mapping tests for compact width, expanded width, folding posture, cutout, navigation insets, Guri-reserved bottom area, and the resulting safe grid viewport.**
- [ ] **Step 3: Run and confirm failure.**

Run: `./gradlew :app:testDebugUnitTest --tests '*GuriPlacementTest' --tests '*AndroidWindowModeMappingTest'`

- [ ] **Step 4: Implement immutable window models and `AndroidWindowModeProvider`.** Keep Android `Rect` and `FoldingFeature` inside Infrastructure and emit Domain coordinates.
- [ ] **Step 5: Persist expanded Guri side with default RIGHT.** Add LEFT/RIGHT settings UI; COMPACT ignores but preserves the setting.
- [ ] **Step 6: Update Home overlay placement.** Pocket remains at the whole-screen configured corner; Guri uses the half center; hit regions never overlap.
- [ ] **Step 7: On any mode, safe-bounds, hinge, or grid viewport change, send `ContextChanged` before recalculating rows/columns or rendering the new position.**
- [ ] **Step 8: Run tests, lint, and build.**

Run: `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleDebug`

- [ ] **Step 9: Commit.**

```bash
git add app/src
git commit -m "feat: add fold-aware guri placement"
```

## Task 10: Reflow Responsive Overflow Across Multiple Home Pages

**Backlog:** `[MVP] 複数ホームページと現在ページ限定フォーカスを実装する`

**Files:**

- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/layout/HomePageIdFactory.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/layout/ManageHomePages.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/application/layout/ReflowHomeLayoutForGrid.kt`
- Create: `app/src/main/java/io/github/okaisan/gurilauncher/presentation/home/HomePager.kt`
- Modify: `HomeLayout.kt`, `HomeViewModel.kt`, `HomeScreen.kt`, `SettingsViewModel.kt`, `LauncherSettingsScreen.kt`, `GestureViewModel.kt`.
- Test: `ManageHomePagesTest.kt`, `ReflowHomeLayoutForGridTest.kt`, `HomePagerTest.kt`, `CurrentPageGestureScopeTest.kt`.

**Interfaces:**

- Consumes: Task 3 `ResponsiveGridResolver.resolve(metrics, placements): ResolvedGrid`, Task 5 Guri, and Task 8 Pocket.
- Produces:

```kotlin
interface HomePageIdFactory {
    fun create(): HomePageId
}

class ReflowHomeLayoutForGrid(
    private val repository: HomeLayoutRepository,
    private val resolver: ResponsiveGridResolver,
    private val idFactory: HomePageIdFactory,
) {
    suspend operator fun invoke(metrics: ResponsiveGridMetrics): ReflowResult
}
```

- [ ] **Step 1: Write page-management tests.** Add creates a unique stable ID, deleting the final page is rejected, deleting current selects the nearest surviving page, reorder preserves placements, and selecting an unknown ID returns a typed error.

- [ ] **Step 2: Write failing overflow reflow tests.**

```kotlin
@Test fun `shrink carries overflow to following pages without hiding apps`() = runTest {
    repository.save(layout(page(APP_A, APP_B), page(APP_C)))
    ReflowHomeLayoutForGrid(repository, resolver, ids)(ResponsiveGridMetrics(1, 1))
    assertEquals(
        listOf(listOf(APP_A), listOf(APP_C), listOf(APP_B)),
        repository.current().pages.map { page -> page.placements.map { it.appId } },
    )
}

@Test fun `expansion does not pull apps back to earlier page`() = runTest {
    val split = layout(page(APP_A), page(APP_B))
    repository.save(split)
    ReflowHomeLayoutForGrid(repository, resolver, ids)(ResponsiveGridMetrics(6, 7))
    assertEquals(split, repository.current())
}
```

- [ ] **Step 3: Run the focused tests and confirm the use case is missing.**

Run: `./gradlew :app:testDebugUnitTest --tests '*ManageHomePagesTest' --tests '*ReflowHomeLayoutForGridTest'`

Expected: FAIL because `ReflowHomeLayoutForGrid` does not exist.

- [ ] **Step 4: Implement forward-only atomic reflow.** Resolve each existing page independently. Keep resolved placements on that page; prepend no content from later pages; append its stable overflow to the next page; cascade overflow; create pages until the carry is empty. Never delete an empty existing page or pull placements backward when capacity grows.

- [ ] **Step 5: Run page and reflow tests.**

Run: `./gradlew :app:testDebugUnitTest --tests '*ManageHomePagesTest' --tests '*ReflowHomeLayoutForGridTest'`

Expected: PASS, with every pre-reflow app ID present exactly once after shrink.

- [ ] **Step 6: Write gesture-scope tests.** Guri snapshots only the current page's resolved candidates on Down. Page or grid viewport changes during Pressing/Active cancel before reflow. Pocket assignments remain global and unchanged.

- [ ] **Step 7: Write Compose pager tests.** Swipe persists `currentPageId`, overlays keep fixed bounds, custom gestures disable swipe, and shrinking the injected viewport reveals overflow on following pages without clipped/hidden apps.

- [ ] **Step 8: Implement `HomePager` with `HorizontalPager`.** Hoist `currentPageId`, keep custom gesture overlays outside the pager, use `userScrollEnabled = !gestureUiState.isActive`, and call reflow only after window-change cancellation.

- [ ] **Step 9: Add page controls to settings and restore persisted page order, anchors, and current page after recreation.**

- [ ] **Step 10: Run unit, UI, lint, and build verification.**

Run: `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleDebug`

Expected: all tasks succeed.

- [ ] **Step 11: Commit.**

```bash
git add app/src
git commit -m "feat: reflow responsive grid across pages"
```

## Task 11: Add Integrated Emulator Verification

**Backlog:** `[MVP] ジェスチャー操作の統合エミュレータ試験を追加する`

**Files:**

- Create: `app/src/androidTest/java/io/github/okaisan/gurilauncher/presentation/GestureLauncherFlowTest.kt`
- Create: `app/src/androidTest/java/io/github/okaisan/gurilauncher/presentation/GestureCancellationFlowTest.kt`
- Create: `app/src/androidTest/java/io/github/okaisan/gurilauncher/presentation/WindowChangeFlowTest.kt`
- Create: `docs/testing/gesture-launcher-emulator-matrix.md`
- Modify: CI workflow that currently builds/tests Android, adding the connected test task to the existing emulator job.

**Consumes:** Completed Tasks 1–10.

**Produces:** repeatable emulator evidence for compact, expanded, fold posture, gesture navigation, and 3-button navigation.

- [ ] **Step 1: Add a deterministic test composition root.** Instrumentation tests inject an in-memory layout/settings repository, deterministic window provider, fake catalog, and recording launcher while production still uses `AndroidAppContainer`.
- [ ] **Step 2: Write the happy-path flow test.** Assign apps, complete Guri hold/slide/release, complete LEFT and RIGHT Pocket flows for capacities 1 and 4, and assert exact launch IDs and one call per gesture.
- [ ] **Step 3: Write cancellation flows.** Cover 419ms release, no selection, PointerCancel, two pointers, Activity recreation/background, page change, window change, removed app, and disabled component with zero launches.
- [ ] **Step 4: Write resizable/foldable assertions.** Inject 320×568dp, 360×800dp, 673×841dp, COMPACT, EXPANDED, and hinge snapshots; assert cancellation occurs before grid recalculation, relative anchors resolve near the same screen position, overflow moves forward without hiding apps, Guri bounds update, and Pocket remains page-independent.
- [ ] **Step 5: Run connected tests on API 26 and API 35 emulator images.**

Run: `./gradlew :app:connectedDebugAndroidTest`

- [ ] **Step 6: Perform the real-adapter smoke matrix and record date/device/result.** Verify HOME selection, current-profile catalog, real app launch, gesture navigation, 3-button navigation, compact/expanded, posture change, uninstall/reinstall, and configuration restoration. Do not store package usage or user-specific app names in committed logs.
- [ ] **Step 7: Add the connected test command to CI and run the repository verification set.**

Run: `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleDebug`

- [ ] **Step 8: Commit.**

```bash
git add app/src/androidTest docs/testing .github/workflows
git commit -m "test: add gesture launcher emulator flows"
```

## Task 12: Expose LOW, STANDARD, and HIGH Sensitivity

**Backlog:** `[Backlog] ジェスチャー感度を3段階で変更できるようにする`

**Files:**

- Create: `app/src/main/java/io/github/okaisan/gurilauncher/domain/gesture/SensitivityPreset.kt`
- Modify: `GestureTuning.kt`, `LauncherSettings.kt`, `LauncherStoredState.kt`, `DataStoreLauncherSettingsRepository.kt`, `LauncherSettingsScreen.kt`, `SettingsViewModel.kt`, `GestureViewModel.kt`.
- Tests: `SensitivityPresetTest.kt`, repository migration/round-trip test, `SensitivitySettingsTest.kt`.

**Consumes:** Tasks 4, 7, 9, and 10.

**Produces:** persisted preset mapped exactly to:

| Preset | Long press | Dead zone | Grid step | Pocket activation |
|---|---:|---:|---:|---:|
| LOW | 520ms | 14dp | 52dp | 14dp |
| STANDARD | 420ms | 10dp | 42dp | 10dp |
| HIGH | 320ms | 6dp | 32dp | 6dp |

- [ ] **Step 1: Write exact mapping tests and assert the default is STANDARD.** Fan radius remains 100dp for every preset.
- [ ] **Step 2: Write persistence tests for every preset and reading an older schema-1 value without an explicit preset.** It maps to STANDARD.
- [ ] **Step 3: Write UI tests for the three mutually exclusive options and active-gesture cancellation when the preset changes.**
- [ ] **Step 4: Run and confirm failure.**

Run: `./gradlew :app:testDebugUnitTest --tests '*SensitivityPresetTest' && ./gradlew :app:connectedDebugAndroidTest`

- [ ] **Step 5: Implement mapping, persistence, settings UI, and state-machine reconstruction.** Snapshot one tuning value at gesture Down; a setting change sends `ContextChanged` and affects the next gesture.
- [ ] **Step 6: Run the complete verification set.**

Run: `./gradlew :app:testDebugUnitTest :app:connectedDebugAndroidTest :app:lintDebug :app:assembleDebug`

- [ ] **Step 7: Commit.**

```bash
git add app/src
git commit -m "feat: add gesture sensitivity presets"
```

## Review Checkpoints

- [ ] **After Wave A:** verify HOME registration is independent from catalog access and neither introduces broad package visibility.
- [ ] **After Wave B:** inspect the serialized schema and confirm GridAnchor permille values and Pocket updates use the same application-scoped DataStore atomically; verify 88dp/104dp sizing boundaries and 6×7 caps.
- [ ] **After Wave C:** review Domain package imports and exhaustive threshold/tie/cancel tests before any pointer UI is merged.
- [ ] **After Wave D:** inspect pointer ownership, exactly-once launch effects, accessibility semantics, and Android system gesture coexistence.
- [ ] **After Wave E:** rotate, resize, change pages, and change fold posture during active gestures; every transition must cancel before responsive reflow and launch nothing. Verify shrink overflow moves only forward and expansion does not pull it back.
- [ ] **Before MVP release:** run unit, lint, build, connected emulator matrix, security/privacy review, and manual HOME-role smoke test.

## Final Acceptance

- [ ] Android can select guri-launcher as the default HOME app on API 26–35.
- [ ] The current profile's launchable apps can be assigned by stable relative GridAnchor and persist across recreation.
- [ ] Guri begins at compact bottom center, activates at STANDARD 420ms, begins unfocused, moves in 42dp 2D steps, and launches the current-page focused app on release.
- [ ] Pocket is visually absent while idle, is configurable LEFT/RIGHT with exactly 1–4 unique assignments, fans icons within the same pointer sequence, and launches only a selected available app on release.
- [ ] Expanded windows place Guri at the configured half's bottom center while Pocket stays at the configured whole-screen corner.
- [ ] Rows and columns adapt to each safe viewport, relative screen positions are preserved, shrink overflow moves to following pages without hiding apps, expansion does not silently pull apps back, Pocket remains global, and page changes cancel active gestures.
- [ ] Android HOME/BACK system gestures remain usable and no `QUERY_ALL_PACKAGES` permission exists.
- [ ] Every cancellation/error path launches zero apps; every successful gesture launches exactly one app.
- [ ] Removed or disabled apps remain in place as unavailable and are never silently replaced.
- [ ] Domain, Application, storage mapping, Compose UI, emulator, lint, and assemble verification all pass.
