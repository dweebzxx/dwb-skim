# macOS Settings UI guidance

**Research cutoff: July 19, 2026.** The recommendations below use stable SwiftUI APIs and avoid depending on Xcode 27/macOS 27 beta-only features.

## Recommended production baseline

For a new SwiftUI macOS app:

1. Declare a dedicated `Settings` scene. It automatically installs the standard App menu command and Command–Comma shortcut and gives the window system settings behavior. ([Apple Developer][1])
2. Use:

   * **One view** for a small settings surface.
   * **`TabView`** for roughly two to five stable categories.
   * **`NavigationSplitView` with a selectable sidebar** only when there are many categories, nested categories, or a persistent preview.
3. Build ordinary panes with **`Form`**, **`Section`**, and **`LabeledContent`**.
4. Use **`Grid`** when controls need exact cross-row baseline and column alignment that `Form` cannot provide.
5. Let controls update settings immediately unless applying them is expensive, disruptive, asynchronous, or requires validating several fields together.
6. Use semantic system fonts, foreground styles, controls, SF Symbols, and materials. Avoid recreating System Settings visually with hard-coded colors, custom glass, or hand-painted rows.
7. Keep the window’s category structure, labels, icons, and row locations stable. Restore the last selected pane.

Apple’s current macOS HIG still describes a noncustomizable toolbar that clearly indicates the active pane, updates the window title, restores the last pane, and avoids placing a Settings button in an ordinary document toolbar. Apple’s SwiftUI documentation implements that model through a `Settings` scene and `TabView`. ([Apple Developer][2])

## 1. Settings scene and category navigation

### Standard implementation

```swift
import SwiftUI

@main
struct ExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }

        Settings {
            SettingsRootView()
                .frame(minWidth: 620, minHeight: 420)
        }
        .defaultSize(width: 700, height: 500)
        .windowResizability(.contentSize)
    }
}

private struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            AdvancedSettingsView()
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
        }
        .scenePadding()
    }
}
```

Apple’s current `Settings` documentation shows the same overall construction and explicitly recommends a `TabView` when settings need multiple collections. It also demonstrates `@AppStorage` for persistent values. ([Apple Developer][1])

### Navigation selection

| Settings scope                               | Recommended navigation                                                      |
| -------------------------------------------- | --------------------------------------------------------------------------- |
| One small pane                               | No category navigation                                                      |
| Two to five categories                       | `TabView` with short labels and SF Symbols                                  |
| Six or more categories                       | `NavigationSplitView` with `List(selection:)`                               |
| Hierarchical settings                        | Sidebar with nonselectable section headings                                 |
| Settings with a central live preview         | Sidebar, detail pane, optional inspector                                    |
| AppKit lifecycle or older deployment targets | `NSTabViewController` or a settings window controller hosting SwiftUI panes |

For sidebar settings, keep category identifiers stable and persist the current selection:

```swift
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case appearance
    case shortcuts
    case advanced

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .shortcuts: "Shortcuts"
        case .advanced: "Advanced"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .shortcuts: "keyboard"
        case .advanced: "gearshape.2"
        }
    }
}

struct SidebarSettingsView: View {
    @AppStorage("selectedSettingsPane")
    private var selection = SettingsPane.general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            detail(for: selection)
                .navigationTitle(selection.title)
        }
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .shortcuts: ShortcutSettingsView()
        case .advanced: AdvancedSettingsView()
        }
    }
}
```

Use this sidebar variant with a macOS 13-or-later deployment target. Older `NavigationView` column styles are deprecated in favor of `NavigationSplitView`. ([Apple Developer][3])

## 2. Form, section, row, and control layout

### Use `Form` first

`Form` applies platform-specific styling to controls. On macOS it produces aligned vertical settings layouts rather than the iOS grouped-list appearance. ([Apple Developer][4])

Two styles are especially useful:

* **`.grouped`**: scrolling, visually grouped sections with leading labels and trailing controls.
* **`.columns`**: non-scrolling, trailing-aligned labels beside leading-aligned values.

Apple describes `.columns` as a non-scrolling two-column form, so wrap it in a `ScrollView` yourself when the content can exceed the window. ([Apple Developer][5])

```swift
struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("updateChannel") private var updateChannel = UpdateChannel.stable
    @AppStorage("displayName") private var displayName = ""

    var body: some View {
        Form {
            Section("Startup") {
                LabeledContent("Launch at login") {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                }

                LabeledContent("Update channel") {
                    Picker("", selection: $updateChannel) {
                        ForEach(UpdateChannel.allCases) { channel in
                            Text(channel.title).tag(channel)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }

            Section("Profile") {
                LabeledContent("Display name") {
                    TextField("Name", text: $displayName)
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 360)
                }

                LabeledContent {
                    Text("Shown in exported reports and shared files.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    EmptyView()
                }
            }
        }
        .formStyle(.grouped)
    }
}
```

`LabeledContent` should be preferred to manually constructed label/control `HStack` rows. It preserves the semantic relationship between the label and value, automatically matches framework controls such as `Picker`, and adapts to the surrounding form style. ([Apple Developer][6])

### Choosing controls

* Use a **checkbox or switch** for a true binary state.
* Use a **menu picker** for a compact, mutually exclusive list.
* Use a **radio group** when all options need to remain visible and the list is short.
* Use a **segmented control** for a very small set of closely related modes, not for lengthy settings labels.
* Use a **slider** when approximate selection is meaningful; show a value when precision matters.
* Use **`ControlGroup`** for adjacent buttons that operate on the same value.
* Keep action buttons next to the value they modify rather than in a distant footer.

Avoid using a disabled-looking text field as read-only information. Prefer `LabeledContent("Path", value: path)` or selectable `Text`.

## 3. Exact alignment with `Grid`

Use `Grid` when a pane mixes fields, menus, buttons, status icons, radio groups, and multiline help text. `Grid` calculates column widths across all rows and supports first-text-baseline alignment, cell anchors, and per-column alignment. ([Apple Developer][7])

```swift
struct AccountSettingsSection: View {
    @Binding var server: String
    @Binding var connectionMode: ConnectionMode

    var body: some View {
        Grid(
            alignment: .leadingFirstTextBaseline,
            horizontalSpacing: 12,
            verticalSpacing: 14
        ) {
            GridRow {
                Text("Server:")
                    .gridColumnAlignment(.trailing)

                VStack(alignment: .leading, spacing: 4) {
                    TextField("example.com", text: $server)
                        .frame(minWidth: 240, idealWidth: 300, maxWidth: 420)

                    Text("Enter a hostname without a protocol or path.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GridRow {
                Text("Connection:")
                    .gridColumnAlignment(.trailing)

                Picker("", selection: $connectionMode) {
                    ForEach(ConnectionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            }

            GridRow {
                Color.clear
                    .frame(width: 1, height: 1)
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                    .accessibilityHidden(true)

                Button("Test Connection") {
                    testConnection()
                }
            }
        }
    }

    private func testConnection() {
        // Perform the test.
    }
}
```

### Alignment rules that consistently look polished

* Align left-column labels **trailing**.
* Align rows using **first text baseline**, not vertical center, when labels sit beside text fields, buttons, or pickers.
* Keep related controls in one leading-aligned `VStack`.
* Give fields and pickers consistent widths within a pane.
* Keep icon-only buttons in fixed square frames.
* Apply `.labelsHidden()` only when an external semantic label already exists.
* Avoid `Spacer()` as the primary alignment mechanism for every row; it causes varying label/control gaps as the window changes width.
* Avoid fixed label widths unless localization has been tested. `Grid` is safer because it derives the label column from content.

## 4. Spacing and dimensions

Apple does not prescribe a single point grid for every settings interface. The following is a practical baseline synthesized from current production apps: CotEditor uses 18-point grid row spacing, Ice centralizes 20-point pane padding and 10-point section spacing, Maccy uses a roughly 450-point content column, and Loop uses a 230-point settings sidebar.

| Element                         |         Practical baseline |
| ------------------------------- | -------------------------: |
| Window content inset            |                   20–24 pt |
| Gap between major sections      |                   20–28 pt |
| Ordinary row spacing            |                   10–14 pt |
| Dense related rows              |                     6–8 pt |
| Control-to-help-text gap        |                     3–5 pt |
| Label-to-control column gap     |                   10–14 pt |
| Sidebar width                   |                 200–240 pt |
| Ordinary field width            |                 220–320 pt |
| Settings detail width           |                 420–580 pt |
| Minimum ordinary window size    |         About 620 × 420 pt |
| Default sidebar settings window | About 760–900 × 500–650 pt |

These values are starting points, not constants. Long localized labels, radio groups, shortcut recorders, and preview panes can require more width.

Use the default **regular** control size throughout most of the window. Use `.small` for dense secondary controls or subordinate information. Reserve `.mini` for tightly constrained auxiliary controls such as an icon-only reset button; using it for ordinary settings reduces clarity and target size.

## 5. Window sizing and responsive behavior

SwiftUI’s default `.automatic` resizability already uses `.contentSize` for a `Settings` scene. Explicitly applying `.windowResizability(.contentSize)` is useful when documenting the intended behavior or when adding minimum and maximum content frames. ([Apple Developer][8])

### Classic tabbed settings

Prefer a compact, content-sized window. Keep pane dimensions reasonably close so the window does not jump dramatically when users change categories.

```swift
Settings {
    SettingsRootView()
        .frame(
            minWidth: 520,
            idealWidth: 620,
            maxWidth: 760,
            minHeight: 320,
            idealHeight: 440,
            maxHeight: 680
        )
}
.windowResizability(.contentSize)
```

### Sidebar settings

Use a stable default size and minimum dimensions. Scroll the detail content rather than continually changing the outer window size.

```swift
Settings {
    SidebarSettingsView()
        .frame(minWidth: 760, minHeight: 480)
}
.defaultSize(width: 840, height: 580)
.windowResizability(.contentSize)
```

Avoid:

* Fixed heights that clip localized or accessibility content.
* A separate nested scroll view around each small section.
* Allowing a live preview to dictate the detail pane’s minimum size.
* Automatically widening the window when an error or help message appears.
* Hiding controls solely to reduce window height when disabling them would preserve context better.

Ice provides a useful production example: its settings window has minimum dimensions of 825 × 500, a default of 900 × 625, and content-size resizability. Its form wrapper adds scrolling only when measured content exceeds the available height.

## 6. Typography, colors, materials, and hierarchy

Use semantic styles rather than fixed font sizes and colors:

```swift
VStack(alignment: .leading, spacing: 4) {
    Text("Automatic updates")
        .font(.body)

    Text("Checks once per day while the app is running.")
        .font(.callout)
        .foregroundStyle(.secondary)
}
```

Recommended hierarchy:

* Pane title: `.title2`, where a visible detail heading is needed.
* Section headings: native `Section` headers or `.headline`.
* Row labels and controls: `.body`.
* Explanatory text: `.callout` or `.caption`, `.secondary`.
* Errors: semantic red plus an icon or explicit “Error” wording; do not communicate solely through color.
* Warnings: a `Label` with an appropriate SF Symbol inside a restrained `GroupBox`.
* Status: icon plus text, not an unlabeled colored dot.

Use:

* `Color.primary`, `.secondary`, `.tertiary` where available.
* The app’s inherited accent tint.
* SF Symbols with an accessibility label or adjacent text.
* Native backgrounds supplied by `Form`, `List`, the window, and sidebar.

Avoid:

* Hard-coded grays such as `Color.gray` for all help text.
* Persistent translucent cards behind every row.
* Custom shadows around ordinary settings sections.
* Decorative separators after every control.
* Manually reproducing Liquid Glass or material colors.

System typography, colors, and materials adapt to appearance, contrast, accent-color, and transparency preferences; semantic styles preserve that behavior. ([Apple Developer][9])

## 7. Reusable SwiftUI components

Centralize small presentation rules rather than wrapping the entire settings framework.

```swift
struct SettingsHelpText: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsIconButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct SettingsStatusLabel: View {
    enum Status {
        case ready
        case warning
        case error

        var image: String {
            switch self {
            case .ready: "checkmark.circle"
            case .warning: "exclamationmark.triangle"
            case .error: "xmark.circle"
            }
        }
    }

    let status: Status
    let message: LocalizedStringKey

    var body: some View {
        Label(message, systemImage: status.image)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
```

Good reusable abstractions include:

* Help text.
* Status labels.
* Icon-only row actions.
* Section headers with optional trailing actions.
* Validated field content.
* Async action controls with progress state.
* A consistent warning or informational callout.

Avoid a large custom `SettingsRow` abstraction that removes the native semantics of `Form`, `LabeledContent`, `Toggle`, or `Picker`. Custom wrappers should preserve labels, focus, enabled state, control size, and accessibility behavior.

## 8. Accessibility, keyboard use, focus, and VoiceOver

SwiftUI automatically exposes basic accessibility information for standard controls. Custom layouts still need explicit semantic relationships and testing. ([Apple Developer][10])

### Label custom grid rows

CotEditor uses `accessibilityLabeledPair` when a visual label and control are separate grid elements. This prevents VoiceOver from treating them as unrelated objects.

```swift
struct LabeledPickerRow: View {
    @Namespace private var accessibilityPair
    @Binding var selection: Mode

    var body: some View {
        GridRow {
            Text("Mode:")
                .gridColumnAlignment(.trailing)
                .accessibilityLabeledPair(
                    role: .label,
                    id: "mode",
                    in: accessibilityPair
                )

            Picker("", selection: $selection) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .accessibilityLabeledPair(
                role: .content,
                id: "mode",
                in: accessibilityPair
            )
        }
    }
}
```

Apple explicitly provides `accessibilityLabeledPair` for matching separate label and content elements. ([Apple Developer][11])

### Focus invalid input

```swift
private enum Field: Hashable {
    case server
    case port
}

@FocusState private var focusedField: Field?

private func apply() {
    if server.isEmpty {
        focusedField = .server
        return
    }

    if !(1...65_535).contains(port) {
        focusedField = .port
        return
    }

    save()
}
```

Use `focusSection()` where a visually grouped cluster should be traversed as a unit. By default, keyboard focus generally follows layout order; `focusSection()` lets descendants be visited before focus moves outside the section. ([Apple Developer][12])

### Accessibility requirements

* Every icon-only button needs `.accessibilityLabel`.
* Add `.accessibilityValue` for custom sliders, progress states, or compound controls.
* Use `.accessibilityHint` only when the consequence is not clear from the label.
* Keep visually hidden control labels semantically available.
* Mark decorative icons and layout placeholders `.accessibilityHidden(true)`.
* Do not remove focus rings.
* Test Tab and Shift–Tab order.
* Test with Full Keyboard Access both enabled and disabled.
* Test VoiceOver rotor order and value announcements.
* Test increased contrast and reduced transparency.
* Test long localized strings and right-to-left layout.

On macOS, `.help("…")` supplies a help tag and also contributes an accessibility hint, but important explanations should remain visibly present rather than existing only as tooltips.

## 9. Validation, disabled states, reset, and destructive actions

### Inline validation

Keep the message next to the field, reserve enough space to prevent dramatic reflow, and explain how to correct the value.

```swift
private var portError: String? {
    guard !(1...65_535).contains(port) else {
        return nil
    }

    return "Enter a port from 1 through 65,535."
}

VStack(alignment: .leading, spacing: 4) {
    TextField("Port", value: $port, format: .number)
        .frame(width: 90)
        .focused($focusedField, equals: .port)

    if let portError {
        Label(portError, systemImage: "exclamationmark.circle")
            .font(.callout)
            .foregroundStyle(.red)
            .accessibilityLabel("Error: \(portError)")
    }
}
```

### Disabled dependencies

Keep dependent controls visible when their relationship teaches users what the parent setting enables:

```swift
Toggle("Use proxy", isOn: $usesProxy)

LabeledContent("Proxy server") {
    TextField("proxy.example.com", text: $proxyServer)
        .frame(width: 280)
}
.disabled(!usesProxy)
```

Hide a control only when it is irrelevant rather than temporarily unavailable.

### Asynchronous actions

Disable only the affected action, prevent repeated submissions, and show progress in the same row:

```swift
HStack(spacing: 8) {
    Button("Test Connection") {
        Task {
            isTesting = true
            defer { isTesting = false }
            await testConnection()
        }
    }
    .disabled(isTesting || server.isEmpty)

    if isTesting {
        ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Testing connection")
    }
}
```

Ice demonstrates this pattern with an Apply button disabled until a value changes, an in-row progress indicator, a separately disabled reset button, tooltip help, and a visible warning about disruptive consequences.

### Reset and destructive settings

```swift
@State private var confirmsReset = false

Button("Restore Defaults…") {
    confirmsReset = true
}
.confirmationDialog(
    "Restore all settings?",
    isPresented: $confirmsReset
) {
    Button("Restore Defaults", role: .destructive) {
        restoreDefaults()
    }

    Button("Cancel", role: .cancel) {}
} message: {
    Text("Custom shortcuts, appearance settings, and account options will be removed.")
}
```

Use a destructive role only when the action causes meaningful data loss or cannot easily be undone. A harmless “Reset this slider” action generally should not be red. Confirmation dialogs should name the exact scope and consequence rather than asking a generic “Are you sure?”

Ordinary preferences should usually persist immediately. An explicit **Apply** action is justified when:

* Several fields must validate together.
* Applying causes a relaunch or logout.
* Applying restarts services or other applications.
* A network or security operation is required.
* Users need to preview and then commit a group of edits.

## 10. Production details that distinguish a finished interface

A polished settings page should also include:

1. **Localization-ready widths.** Test German, Finnish, French, Arabic, and Japanese rather than sizing only for English.
2. **Stable conditional layout.** Avoid having entire sections jump when one toggle changes.
3. **Persistence semantics.** Clearly decide whether each value is immediate, staged, restart-required, or server-backed.
4. **External-change handling.** Refresh values when defaults, accounts, permissions, or managed settings change outside the window.
5. **Permission states.** Show status, explanation, and an explicit button to open the appropriate System Settings location.
6. **Restart communication.** State whether a change applies immediately, to new windows, or after relaunch.
7. **Busy and failure states.** Async controls need progress, cancellation where useful, and recoverable errors.
8. **Default actions.** Give modal Done/Save actions `.keyboardShortcut(.defaultAction)` and ensure Escape cancels where cancellation is valid.
9. **Help.** Provide visible explanations for uncommon settings and a help link for complex concepts.
10. **Testing.** Add accessibility identifiers only where UI tests need stable selectors; do not use them as substitutes for accessibility labels.
11. **No prototype placeholders.** Avoid unlabeled icons, arbitrary fixed widths, truncated help text, raw error strings, and controls that silently do nothing.
12. **Visual regression testing.** Capture light/dark, each supported macOS release, empty/error/busy states, and long localization variants.

CotEditor’s settings source demonstrates several of these finishing details together: restart confirmation, visible secondary descriptions, multiline sizing, labeled status indicators, help links, accessibility label/content pairing, and default-action keyboard shortcuts.

# Source guide

## Apple HIG: Settings

**Technique:** Use the App menu’s standard Settings command, stable pane navigation, a clearly selected category, pane-specific titles, and restoration of the last pane.

**Polish benefit:** Users can predict where settings live and can return to previously adjusted options without relearning the window.

**Version/limits:** Design guidance rather than an API requirement. The HIG describes the classic toolbar-pane model; use a sidebar only when the information volume materially warrants it.

**Production:** Strongly recommended. ([Apple Developer][2])

## Apple SwiftUI `Settings` documentation and MacLandmarks tutorial

**Technique:** Declare `Settings { … }`, store ordinary preferences with `@AppStorage`, and use `TabView` for categories.

**Polish benefit:** Correct menu command, keyboard shortcut, window treatment, lifecycle, and persistence with little custom code.

**Version/limits:** `Settings` arrived with the SwiftUI app lifecycle in macOS 11. The newest `Tab` declaration syntax requires newer SDKs; `.tabItem` remains suitable for broader deployment.

**Production:** Preferred foundation for new SwiftUI apps. ([Apple Developer][1])

## Apple `Form`, grouped/columns styles, and `LabeledContent`

**Technique:** Use `.grouped` for visually separated scrolling sections, `.columns` for compact two-column forms, and `LabeledContent` for semantic label/value rows.

**Polish benefit:** Native control styling, consistent label columns, correct spacing, and better adaptation when Apple changes macOS control appearance.

**Version/limits:** Use a macOS 13-or-later deployment target for the complete modern combination without compatibility branches. `.columns` does not scroll.

**Production:** Strongly recommended before building custom row components. ([Apple Developer][5])

## Apple `Grid`

**Technique:** Build a shared label/control grid using `.leadingFirstTextBaseline`, trailing label alignment, and controlled horizontal and vertical spacing.

**Polish benefit:** Precisely aligns mixed controls and multiline values across every row.

**Version/limits:** Requires macOS 13+. Grid eagerly creates its cells; settings panes are normally small enough that this is appropriate.

**Production:** Recommended when `Form` cannot meet precise alignment requirements. ([Apple Developer][7])

## Apple window sizing guidance

**Technique:** Constrain top-level content and use `defaultSize` and content-derived resizability.

**Polish benefit:** Prevents tiny unusable windows, unnecessary giant windows, and clipping while retaining platform window behavior.

**Version/limits:** Settings scenes already use content-size resizability under the automatic strategy.

**Production:** Recommended; avoid taking direct ownership of `NSWindow` solely to establish basic dimensions. ([Apple Developer][8])

## Apple accessibility and focus documentation

**Technique:** Preserve native controls, pair separate labels and content, expose custom values, group focusable sections, and use `FocusState` to direct users to validation failures.

**Polish benefit:** Correct VoiceOver announcements and predictable keyboard navigation also tend to improve the structural quality of the visual layout.

**Version/limits:** Availability varies by modifier. The primary APIs used here are stable on the recommended macOS 13+ baseline.

**Production:** Required. ([Apple Developer][11])

## Apple WWDC22: SwiftUI forms in AppKit apps

**Technique:** Incrementally host a SwiftUI `Form` as a standalone settings interface inside an existing AppKit application.

**Polish benefit:** Gains the current macOS settings appearance without rewriting the rest of the application.

**Version/limits:** The presentation discussed with the new grouped settings style corresponds to macOS Ventura-era APIs.

**Production:** Recommended for incremental AppKit adoption. ([Apple Developer][9])

# Open-source implementations worth studying

## CotEditor

The current CotEditor release is **7.0.7, released July 13, 2026**, and requires macOS 15 or later. ([CotEditor][13])

Its settings code is the strongest reference here for a native, precise layout:

* `Grid(alignment: .leadingFirstTextBaseline, verticalSpacing: 18)`.
* Trailing-aligned label column.
* Nested leading-aligned control groups.
* Visible secondary help text with multiline sizing.
* `accessibilityLabeledPair` for separate labels and controls.
* Restart confirmation for behavior-changing preferences.
* Radio groups and menu pickers selected according to content.
* Status icon, status text, tooltip, and accessibility hint used together.
* Help links and keyboard default actions.

**Production recommendation:** Highly recommended as a source-code reference, especially for complex panes. Copy the structural ideas, not app-specific dependencies.

## Ice

Ice supports macOS 14 and later. Its settings implementation uses a selectable `NavigationSplitView`, adapts sidebar widths and row heights to the user’s sidebar-row-size setting, and maintains a stable detail area. ([GitHub][14])

Notable techniques:

* Centralized pane padding, spacing, and toggle presentation.
* Detail views selected from a stable enum.
* Conditional settings accompanied by explanatory annotations.
* Apply/reset/progress behavior for disruptive operations.
* Conditional scrolling based on measured content.
* Explicit minimum and default window sizes.

**Limitations:** Its custom form and mini switch style require careful accessibility and target-size review.

**Production recommendation:** Recommended for studying larger sidebar-based settings windows; do not adopt all custom styling automatically.

## Maccy and the `Settings` package

Maccy supports macOS 14 or later and currently uses the open-source `sindresorhus/Settings` package. ([GitHub][15])

Its general pane demonstrates:

* A consistent 450-point content region.
* Reusable sections and dividers.
* Fixed-width menu pickers.
* Keyboard-shortcut recorders with help tags.
* Secondary multiline explanatory copy.
* Links into System Settings.

The package also provides `Settings.Container` and `Settings.Section`, designed to produce alignment similar to AppKit’s `NSGridView`, and can mix SwiftUI panes with AppKit view controllers. It supports much older macOS releases than the modern native SwiftUI pattern.

**Production recommendation:** Good for an existing AppKit lifecycle, mixed SwiftUI/AppKit application, or legacy deployment requirement. A new macOS 13+ SwiftUI app should generally start with the native `Settings` scene instead.

## Loop

Loop supports macOS 13 and later and uses a custom three-region settings design: a 230-point sidebar, a 390-point settings pane, and an optional 520-point live preview inspector. ([GitHub][16])

Its most reusable technique is placing preview content in an overlay so the preview does not influence the dimensions of the surrounding settings layout.

**Limitations:** It uses a third-party window framework, custom materials, fixed region widths, and direct `NSWindowController` management.

**Production recommendation:** Study it when a continuously updating visual preview is a core part of settings. It is not the recommended baseline for an ordinary preferences window.

## AppKit approach when it materially helps

Use AppKit when you need:

* macOS releases predating the modern SwiftUI APIs.
* An existing `NSApplicationDelegate` and `NSWindowController` lifecycle.
* Mixed AppKit and SwiftUI panes.
* `NSTabViewController` toolbar-pane behavior.
* Precise responder-chain integration with existing AppKit commands.
* Controls that still lack adequate SwiftUI equivalents.

For strict label/control alignment in an AppKit pane, `NSGridView` remains a practical solution. The `sindresorhus/Settings` package explicitly recommends it and supplies hosting support for SwiftUI panes.

For a new application with a macOS 13+ minimum, AppKit rarely improves an ordinary settings interface enough to justify owning the window and navigation infrastructure yourself.