# macOS 27 changelog

Changes in this fork, newest first. See [MACOS27.md](MACOS27.md) for how the
macOS 27 support works, and the releases page for builds.

## 2026-09-17

### The Ice Bar shows real icons again

- **Positions now come from MenuBarAgent.** Each app publishes its status items
  under its own `AXExtrasMenuBar`, but macOS 27 draws them from MenuBarAgent,
  and an app keeps reporting the frame its item had before macOS moved it. Items
  that left the system overflow therefore looked stacked on its button, so Ice
  treated them as not drawn and neither photographed nor clicked them correctly.
  MenuBarAgent's own tree, one container per item, carries the real positions.
- **Icons are separated from the menu bar background properly.** The bar is
  translucent, so a crop's background is a piece of wallpaper that changes across
  the crop and can have an edge cutting through it. One background color per crop
  left that wallpaper in the picture as a pale rectangle, and its residual made
  plain white icons look colored, which kept the wallpaper instead of turning the
  icon into a template. The background is now estimated at the top and bottom of
  every column and blended between them, an icon counts as colored only when its
  own pixels carry color, and anything too faint or not connected to a solid part
  of the icon is dropped.
- **A raw crop is never shown.** If the background can't be separated, the Ice
  Bar shows that app's icon instead of a rectangle of wallpaper.
- **Pictures are saved to disk**, under
  `~/Library/Caches/com.jordanbaird.Ice/IceBarImages`, and reused after a
  relaunch, so a crowded menu bar only has to make room once. A photo pass runs
  once per launch and hands the spacer's width back in steps to catch items macOS
  would otherwise never draw. `IceBarNoPhotoApps` lists bundle identifiers whose
  items change too often to be worth photographing.

### Clicking

- **Items are pressed through Accessibility** (`AXPress`, or `AXShowMenu` for a
  right click), which works while macOS isn't drawing them, so the hidden items
  no longer return to the menu bar when you click one in the Ice Bar. Revealing
  and clicking remains the fallback for items that answer neither action.
- **Ice's own button closes the bar.** A click on it reaches MenuBarAgent, so the
  Ice Bar's outside-click monitor closed the bar and the button's action opened
  it again.

### Appearance

- **Liquid Glass** on macOS 26 and later, with two independent settings:
  Darkness picks the shade of the layer over the glass, from white to black, and
  Transparency picks how much of the glass it covers, from bare glass to solid.
- **Icon spacing**, from none to 24 points between the items in the bar.
- Sliders are in the System Settings style: a plain continuous track with a
  symbol at each end, no percentage and no steps.
- Every settings pane has space above its first row again, which on macOS 26 and
  later sat against the window's header.

### Responsiveness

- Dragging an appearance slider no longer catches. Each intermediate value used
  to republish the settings object, which rebuilds the whole pane, including the
  icon menus and the launch-at-login toggle, and saved a preference.
- The menu bar color sample took a screenshot on the main thread every five
  seconds while the settings window was open. It now runs off the main thread.
- A complete accessibility walk of every running app ran just as often, and has
  to run on the main thread. It is skipped while the user is in a settings pane
  that doesn't show the items.

### Known limits

- macOS never draws an item it keeps in its own overflow, so Ice can only
  photograph one while the menu bar has room. Until then the Ice Bar shows that
  app's icon. macOS decides the overflow as a group: if the hidden items don't
  all fit, it draws none of them. Opening the Menu Bar Layout pane is the
  reliable way to let Ice take fresh pictures.
- The search panel, show on hover/click/scroll, auto-rehide, item spacing and
  app-menu hiding remain turned off on macOS 27.
