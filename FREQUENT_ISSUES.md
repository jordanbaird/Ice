# Frequent Issues

### Items are moved to the always-hidden section

By default, macOS adds new items to the far left of the menu bar, which is also the location of Ice's always-hidden section. Most apps are configured
to remember the positions of their items, but some are not. macOS treats the items of these apps as new items each time they appear. This results in
these items appearing in the always-hidden section, even if they have been previously been moved.

Ice does not currently manage individual items, and in fact cannot, as of the current release (`0.9.0`). Once issues
[#6](https://github.com/jordanbaird/Ice/issues/6) and [#26](https://github.com/jordanbaird/Ice/issues/26) are implemented, Ice will be able to
monitor the items in the menu bar, and move the ones it recognizes to their previous locations, even if macOS puts them in a different spot.

### Ice removed an item

Ice does not have the ability to move or remove items. It likely got placed in the always-hidden section by macOS. Option + click the Ice icon to show
the always-hidden section, then Command + drag the item into a different section.

### Ice does not remember the order of items

This is not a bug, but a missing feature. It is being tracked in [#26](https://github.com/jordanbaird/Ice/issues/26).
