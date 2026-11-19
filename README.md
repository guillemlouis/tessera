# Tessera

*Tessera*: a small tile of a mosaic, and in ancient Rome a token or password tablet.

A small macOS menu bar app for everyday developer utilities. Everything runs locally.

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)

## Build and install

```bash
cd ~/Documents/toolbox
bash build.sh --install
```

`build.sh --install` quits the running copy, builds `build/Tessera.app`, installs it in /Applications and starts it. The first lines of its output show the macOS SDK and whether Liquid Glass is native or emulated.

The icon (a 2x2 grid) appears in the menu bar. There is no Dock icon.

## Tools

### GUID
- Press **Generate** (or Return): a new GUID is shown and copied to the clipboard.
- Formats follow .NET `Guid.ToString()`: **D** (hyphens), **N** (digits only), **B** `{braces}`, **P** `(parentheses)`, plus lower or upper case.
- History (up to 200 entries) is stored in UserDefaults. Click a row to copy it again.
- Auto-clear: keep, on quit, 1 hour, 1 day (default), 7 days. The trash button clears immediately.

### JWT
- Paste a token (Paste button, Cmd+Shift+V, or type into the field). A `Bearer ` prefix is stripped.
- Shows header, payload and signature with syntax colouring, plus a live validity panel for `iat`, `nbf` and `exp`.
- Tokens are held in memory only. The signature is **not** verified.

### JSON
- Paste JSON (or leave the field empty to use the clipboard), then **Format** (Command+Return) or **Minify** (Shift+Command+M).
- The result is copied to the clipboard and not displayed. A status line shows the line count and size, or the error with its line and column.
- Indent: 2 spaces, 4 spaces or tab. Key order and number formatting are preserved.

### URL
- Paste an encoded URL (for example from Datadog). It is decoded into a **Readable** URL (copy button), the **Path** (each resource with its ID; click a row to copy the ID) and the **Query** (one parameter per line).
- OData expressions such as `$filter` are broken onto lines at each `or` / `and` and indented by nesting. URLs encoded twice are handled.

## Settings

The `...` menu holds **Launch at login** and **Quit**.

## Design

- Native controls (segmented pickers, buttons, menus, progress bars), San Francisco fonts and system colours. The app follows Light and Dark mode.
- On macOS 26 the panel and action buttons use Liquid Glass. This needs the macOS 26 SDK (Xcode 26 command line tools, Swift 6.2). With older tools or older macOS, the same views use the system materials and bordered buttons.
- Content is grouped in rounded sections (`PanelSection`), like System Settings. Shared components live in `Sources/Theme.swift`.

## Conventions

- **Select to copy (app-wide):** every displayed value uses `SelectableText` (`Sources/SelectableText.swift`). Selecting text with the mouse, on one line or several, copies it as soon as the mouse is released. Where it makes sense, a plain click copies the whole line. Every copy shows the green "copied" indicator in the header.
- Copies always go through `Clipboard.copy(_:)`.

## Adding a tool

1. Add a case to `Tool` in `RootView.swift`.
2. Create a view and add it to the `switch` in `RootView.body`.
