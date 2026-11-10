# Виправлення для `MACOS27-PREVIEW.md`

Дата: 2026-11-04 · Файл живе не тут: `preview-doc` і `fork/main`. PR #995 зібрано з
`fork/macos-27-support`. Ці заміни переносяться туди окремим рішенням; складання й
публікація нової збірки потребують окремого дозволу користувача.

## Заміна 1 — перетягування

**Було** (у розділі «What to expect, honestly»):

> - **Items cannot be dragged around the bar.** macOS 27 arranges them itself; which section an
>   application belongs to comes from a saved layout instead of its position.

**Стало:**

> - **Which section an application belongs to comes from a saved layout**, not from where its item
>   sits on the bar. The order within a section is still yours: a ⌘ drag in the menu bar works on
>   macOS 27 and the new order holds. What you cannot drag is an item that is currently hidden —
>   macOS takes it off the bar entirely, so there is nothing under the pointer until its section is
>   showing. Ice never rearranges the bar on its own: the move is a gesture with the real pointer,
>   and it is not worth taking that from you unasked.

**Підстава.** Виміряно 2026-11-04 на macOS 27.2. ⌘-перетягування справжнього значка на
зовнішньому екрані міняє порядок, і новий порядок лишається — однаково при запущеному і
зупиненому Ice. Синтетичний ⌘-drag (клавіатурна подія ⌘ перед натисканням, далі
`leftMouseDown` → серія `leftMouseDragged` → `leftMouseUp`) перемістив
`com.apple.TextInputMenuAgent` з `x=1537` на `x=1490`, помінявши його місцями зі значком
Stats; зворотний drag повернув смугу точно в початковий порядок.

Попередня заява спиралася на спостереження, що значок **ад-хок підписаного** процесу не
рухається — ні рукою, ні програмно. Це правда, але стосується лише таких процесів і не
поширюється на звичайні застосунки.

## Заміна 2 — пошук і відступи

**Було:**

> - Search, item spacing and hiding the application menus are off on macOS 27.

**Стало:**

> - **Hiding the application menus is off on macOS 27**, on purpose: macOS folds the items that do
>   not fit by itself, so shown items never cover the menus, and switching it on only took keyboard
>   focus from whatever you were using.
> - Search and item spacing work. Spacing respaces the applications whose items are showing;
>   a hidden application keeps the old spacing until it is restarted, because Ice will not force
>   quit an application you cannot see.

**Підстава.**

*Пошук* ніде в коді не вимкнений. `MenuBarSearchPanel` створюється безумовно в
`MenuBarManager`, список бере з `itemManager.itemCache.managedItems` (на macOS 27 його
заповнює `Concealer27.cacheFromSavedLayout`), картинки — з `ItemImageStore27`, а вибір
значка виконує через `itemManager.click` → `ItemClicker27`.

*Відступи.* AppKit на macOS 27 досі читає `NSStatusItemSpacing`: пробний значок завширшки
24 pt лягає шириною 40 pt зі стандартним padding і 54 pt з `NSStatusItemSpacing = 30`.
Ламався перезапуск застосунків — `MenuBarItemSpacingManager.applyOffset` обривав перебір
`break`-ом замість `continue` на Control Center або на самому Ice, і решта застосунків не
перезапускалась. Баг апстрімовий (`b1a5bf7`, 2024-09-15, є на `origin/main`), псує й
macOS 26; виправлено окремим комітом, придатним до подання апстріму як є.

## Доповнення 2026-11-05 — відступи прибрано з macOS 27

Заміна 2 вище описує гілку, опубліковану в PR #995, і для неї лишається правдивою. Локальна
`macos-26` відтоді **прибрала сам повзунок відступів на macOS 27**: AppKit читає
`NSStatusItemSpacing` у момент створення значка і більше ніколи, тож єдиний спосіб змінити
проміжок — закрити й запустити кожен застосунок зі значком, а прихований застосунок на 27 не
публікує значка взагалі, не потрапляє в перелік для перезапуску і лишається зі старим відступом
усе одно. Рішення користувача: перезапускати все заради двох точок — не та ціна.

Тому **якщо цей коміт колись піде в публікацію, Заміну 2 треба переписати**: другий абзац про
«Search and item spacing work» має сказати, що працює пошук, а відступи на macOS 27 не
пропонуються, і чому. `MenuBarItemSpacingManager` і виправлення `break` → `continue` лишаються
як є — вони потрібні macOS 26 і придатні до подання апстріму незалежно від цього.
