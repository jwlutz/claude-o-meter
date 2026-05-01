# ClaudeMeter

Mac menu-bar app + desktop widget showing how much of your Claude Code 5-hour
and weekly usage you've burned through, with a glance-able pie chart and a
countdown to reset.

Reads `~/.claude/projects/**/*.jsonl` directly — no API calls, no network.

## Layout

```
ClaudeMeter/
  Package.swift                        # SwiftPM: builds the menu-bar exe
  Sources/
    ClaudeMeterCore/                   # shared models + log parser
      UsageSnapshot.swift              #   data model + plan limits
      UsageReader.swift                #   JSONL parser → UsageSnapshot
      Formatting.swift                 #   "2h14m", "120k" helpers
    ClaudeMeterApp/                    # menu-bar executable
      main.swift, AppDelegate.swift    #   NSStatusItem + popover wiring
      MenuBarIcon.swift                #   tiny pie + countdown
      PopoverView.swift                #   click-through full breakdown
      PieChart.swift                   #   SwiftUI pie + ring views
      UsageStore.swift                 #   ObservableObject, FSEvents watcher
    ClaudeMeterWidget/                 # widget source (not yet a target)
      ClaudeMeterWidget.swift          #   small + medium widget entry
      SharedPie.swift                  #   pie duplicated for widget target
```

## Run the menu-bar app today

```bash
cd ~/Desktop/ClaudeMeter
swift run ClaudeMeter
```

A pie + countdown should appear in the menu bar. Click it for the full
breakdown popover. Quit from the popover.

> Running via `swift run` shows a Dock icon briefly — to make it a true
> "menu-bar only" app, build a proper `.app` bundle (see next section).

## Package as a real `.app` (LSUIElement, login item)

The menu bar app already calls `NSApp.setActivationPolicy(.accessory)` so
no Dock icon appears at runtime. To register it as a login item and ship
it to other machines:

1. `File > New > Project > macOS > App` in Xcode.
2. Drag the four files from `Sources/ClaudeMeterApp` and the contents of
   `Sources/ClaudeMeterCore` into the new target.
3. In `Info.plist`, set `Application is agent (UIElement)` = `YES`.
4. To launch on login: `SMAppService.mainApp.register()` (macOS 13+).

## Adding the desktop widget

WidgetKit widgets live in their own bundle; SwiftPM can't produce one,
so the widget needs an Xcode target.

1. In the same Xcode project, `File > New > Target > Widget Extension`.
   Uncheck "Include Configuration Intent" for the simplest path.
2. Drag `Sources/ClaudeMeterWidget/*.swift` into the widget target.
3. Add `ClaudeMeterCore`'s files to the widget target as well (or extract
   them into a framework that both targets link).
4. Enable the `App Groups` capability on **both** targets and add a group
   like `group.com.you.claudemeter`. The widget runs sandboxed and cannot
   read `~/.claude` directly, so:
   - From the menu-bar app, write a JSON snapshot into the App Group
     container after each refresh.
   - In `UsageProvider.load()`, decode that JSON instead of running
     `UsageReader()` live.

Once that's wired, drag the widget to the desktop (macOS 14+) or the
Notification Center.

## Token budgets

The 5-hour and weekly token budgets in `PlanLimits` are estimates — Anthropic
doesn't publish exact caps. Defaults are conservative for a Max plan; tune in
`UsageSnapshot.swift` or expose a Settings pane later.

## Reset semantics

The 5-hour window is rolling: it resets 5h after the **first** assistant
message in the current window. `WindowUsage.resetAt` reflects that.
