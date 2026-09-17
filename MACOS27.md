# macOS 27 support

macOS 27 moved every status item into `MenuBarAgent`, which draws them into a
single bar. There are no per-item windows any more, and an oversized status
item (Ice's old 10,000-point divider) is discarded instead of pushing other
items off screen. This is why older Ice builds show "Loading menu bar items"
and hide nothing on macOS 27.

This branch builds on the upstream `macos-26` branch and the experimental
macOS 27 work from [jordanbaird/Ice#980](https://github.com/jordanbaird/Ice/pull/980),
with additional hardening. Every macOS 27 path is gated on
`#available(macOS 27.0, *)`.

## What works on macOS 27

- Hiding and showing the Hidden section with Ice's button or a hotkey.
- The Ice Bar: clicking Ice's button shows the hidden items in a bar below it.
  On macOS 26 and later it is drawn with Liquid Glass, with Darkness and
  Transparency settings.
- The Menu Bar Layout editor: item thumbnails and moving items between sections.
- Menu bar appearance settings.
- Native input for every other item. The clock still opens Notification Center.

## What doesn't

- The search panel, show on hover/click/scroll, auto-rehide, item spacing and
  app-menu hiding are disabled on macOS 27.
- Without the Ice Bar, hidden items move into Apple's native overflow (the «
  button), so they are still reachable from there.
- Items that macOS keeps in its own overflow aren't drawn anywhere, so they can
  only be photographed while the menu bar has room for them. Until then the Ice
  Bar shows their app's icon. macOS overflows the group as a whole: it draws
  none of those items unless all of them fit.
- Clock, Control Center and other items hosted by `MenuBarAgent` can't be
  dragged from the Layout editor. You can still Command-drag them yourself.
- Opening the Layout editor shows every item until you leave it.

## How it works

**Enumeration.** Items are read through Accessibility from each running app's
extras menu bar. Items without a stable identifier are tracked by process-local
AX equality. MenuBarAgent's overflow button is excluded.

**Geometry.** An app's own extras menu bar keeps reporting the frame its item
had before macOS moved it, so items that leave the system overflow still look
stacked on its button. Positions therefore come from MenuBarAgent's own
accessibility tree: one window per display, one container per item, each
nesting the owning app's element. An item whose container overlaps the overflow
button or another container is treated as not drawn.

**Hiding.** Ice owns a blank status item immediately to the left of its visible
button. To hide, Ice widens it so `MenuBarAgent`'s own overflow takes everything
to its left, sized from Ice's position relative to the notch. To show, Ice
withdraws it, because even a one-point item reserves a visible slot. Changes are
coalesced to one every 300 ms so rapid clicks don't stack overflow animations.
No private API is used.

**Alignment.** Before hiding, Ice checks through its own accessibility frames
that the blank item sits directly left of its button. If it doesn't, Ice moves
only its own blank item with one native Command-drag. System hit testing returns
MenuBarAgent's unidentified host element there, so the drag is accepted only when
that element's frame matches Ice's own boundary frame.

**Ice Bar.** In Ice Bar mode the hidden items stay concealed, and only the bar
opens and closes. Clicking an item presses it through Accessibility, so nothing
returns to the menu bar. Only an item that answers neither `AXPress` nor
`AXShowMenu` falls back to revealing the items and clicking where MenuBarAgent
draws them.

**Thumbnails.** Other apps' status item images aren't available through any
API. One Retina screenshot of the menu bar strip is cropped using each item's
container frame. The menu bar is translucent, so the background is estimated at
the top and bottom of every column and blended between them; a glyph counts as
colored only when its own pixels carry chroma, and anything too faint, or not
connected to a solid part of the glyph, is dropped. A raw crop is never shown.

Concealed items aren't drawn, so pictures are taken just before concealing,
whenever items are revealed, and by a photo pass that runs once per launch: it
gives the spacer's width back in steps so macOS draws the concealed items long
enough to photograph them, then restores it. Pictures are saved under
`~/Library/Caches/com.jordanbaird.Ice/IceBarImages` and reused after a relaunch,
so a crowded menu bar only has to make room once. The `IceBarNoPhotoApps`
default lists bundle identifiers whose items change too often to photograph.
Screen Recording is only needed for these images.

## Hardening in this branch

- Ice never drags its boundary without a user action. Launch and background
  refreshes leave items expanded if alignment would need a drag.
- Native drags and clicks wait until no modifiers or buttons are held and
  nothing was typed in the last half second. Keyboard input is suppressed while
  the synthetic Command key is down.
- The Layout editor can't drag items hosted by `MenuBarAgent`. Synthetic drags
  of those items crashed `MenuBarAgent` during testing of #980.
- After a spacer is widened, Ice confirms that its own button is still on the
  bar; otherwise it withdraws the spacers and shows everything.
- `MenuBarItemService` accepts ad-hoc-signed builds
  ([jordanbaird/Ice#950](https://github.com/jordanbaird/Ice/pull/950)).
- Probe tools that posted real input or used the private assessment-mode API
  were removed.

## Troubleshooting

Set `defaults write com.jordanbaird.Ice DebugDumpMacOS27Glyphs -bool true` to
write menu bar captures, per-item crops and their frames to
`~/Library/Caches/com.jordanbaird.Ice/GlyphDebug`.

## Building

You need Xcode 27. SwiftUI's `@State` is a macro in the macOS 27 SDK, and its
plugin only ships with Xcode, so Command Line Tools can't build Ice.

To build a locally signed copy without an Apple Developer team:

```sh
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  ENABLE_HARDENED_RUNTIME=NO \
  build
```

Hardened runtime has to be off for an ad-hoc build. Otherwise library validation
refuses to load the embedded Sparkle framework, which keeps Sparkle's own Team
ID, and Ice crashes at launch with "Library missing".

Copy `build/Build/Products/Release/Ice.app` to `/Applications`, then grant
Accessibility (required) and Screen Recording (optional) when asked. An ad-hoc
signature changes on every build, so macOS may ask for these permissions again
after you rebuild.

## Unit tests

The decision logic has standalone tests that build with `swiftc`:

```sh
xcrun swiftc -O Ice/MenuBar/MenuBarItems/MacOS27NativeBoundary.swift \
  Tests/NativeMenuBarBoundaryTests.swift -o /tmp/ice-boundary-tests && /tmp/ice-boundary-tests
xcrun swiftc -O Ice/MenuBar/LayoutBar/MenuBarGlyphImage.swift \
  Tests/MenuBarGlyphImageTests.swift -o /tmp/ice-glyph-image-tests && /tmp/ice-glyph-image-tests
```

## Attribution

The macOS 27 compatibility work is by PWB97 in
[jordanbaird/Ice#980](https://github.com/jordanbaird/Ice/pull/980).
Accessibility enumeration was adapted from the GPLv3
[Thaw project](https://github.com/thaw-app/Thaw).
