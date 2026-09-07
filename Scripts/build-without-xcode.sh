#!/bin/zsh
#
# build-without-xcode.sh
# Builds Ice.app from this repository using only the Command Line Tools
# (swift/swift build + Swift Package Manager), for machines without a
# full Xcode installation.
#
# Notes:
#   - Xcode's actool is required to compile Assets.xcassets, so the
#     compiled Assets.car is extracted from the official 0.11.13-dev.2
#     release archive and cached under .clt-build/assets. The app icon
#     (.icns) is generated locally from the PNGs in the repo via iconutil.
#   - The resulting app is ad-hoc signed, so macOS treats it as a new app
#     for privacy permissions (grant Screen Recording after first launch).
#   - Output: build/Ice.app
#
set -euo pipefail

ROOT="${0:A:h:h}"
STAGE="$ROOT/.clt-build"
BUILD="$STAGE/build"
OUT_APP="$ROOT/build/Ice.app"
ASSETS_URL="https://github.com/jordanbaird/Ice/releases/download/0.11.13-dev.2/Ice.zip"
ASSETS_ZIP="$STAGE/assets/Ice-0.11.13-dev.2.zip"
# Integrity pin for the downloaded asset archive (Ice 0.11.13-dev.2).
ASSETS_SHA256="c1bbaa71f61ebfe5ee928f790af60963a9f202364d63f78d2c6b3ec5105cf4a0"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1 }

# ---------------------------------------------------------------- versions
MARKETING_VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$ROOT/Ice.xcodeproj/project.pbxproj" | head -1 | tr -d '"')
CURRENT_PROJECT_VERSION=$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);.*/\1/p' "$ROOT/Ice.xcodeproj/project.pbxproj" | head -1)
[[ -n "$MARKETING_VERSION" && -n "$CURRENT_PROJECT_VERSION" ]] || die "could not read version from project"
log "Ice $MARKETING_VERSION ($CURRENT_PROJECT_VERSION)"

# ---------------------------------------------------------------- proxy
# Use the system HTTP proxy (if any) for GitHub access; SPM needs it on
# networks where GitHub is slow.
PROXY_PORT=$(scutil --proxy | awk '/HTTPPort/ {print $3}')
if [[ -n "$PROXY_PORT" ]] && nc -z 127.0.0.1 "$PROXY_PORT" 2>/dev/null; then
    export https_proxy="http://127.0.0.1:$PROXY_PORT" http_proxy="http://127.0.0.1:$PROXY_PORT"
    log "using proxy 127.0.0.1:$PROXY_PORT for downloads"
fi

# ---------------------------------------------------------------- stage sources
# .build is preserved across runs for incremental rebuilds.
log "staging sources"
rm -rf "$BUILD/Sources"
mkdir -p "$BUILD/Sources/IceApp" "$BUILD/Sources/MenuBarItemService" "$STAGE/assets"

copy_swift() { rsync -a --include='*/' --include='*.swift' --exclude='*' "$1" "$2" }
copy_swift "$ROOT/Ice/"               "$BUILD/Sources/IceApp/"
copy_swift "$ROOT/Shared/"            "$BUILD/Sources/IceApp/"
copy_swift "$ROOT/MenuBarItemService/" "$BUILD/Sources/MenuBarItemService/"
copy_swift "$ROOT/Shared/"            "$BUILD/Sources/MenuBarItemService/"
cp "$ROOT/Scripts/clt-build-support/ImageResourceShim.swift" "$BUILD/Sources/IceApp/"

cat > "$BUILD/Package.swift" <<'EOF'
// swift-tools-version: 5.9
// Staging manifest for CLT-only builds of Ice. Not used by the Xcode project.
import PackageDescription

let package = Package(
    name: "Ice",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2"),
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.0.0"),
        .package(url: "https://github.com/tmandry/AXSwift", from: "0.3.2"),
        .package(url: "https://github.com/buh/CompactSlider", from: "1.1.5"),
        .package(url: "https://github.com/ukushu/Ifrit", from: "2.0.3"),
        .package(url: "https://github.com/groue/Semaphore", from: "0.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "IceApp",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "LaunchAtLogin", package: "LaunchAtLogin-Modern"),
                .product(name: "AXSwift", package: "AXSwift"),
                .product(name: "CompactSlider", package: "CompactSlider"),
                .product(name: "IfritStatic", package: "Ifrit"),
                .product(name: "Semaphore", package: "Semaphore"),
            ],
            path: "Sources/IceApp"
        ),
        .executableTarget(
            name: "MenuBarItemService",
            dependencies: [
                .product(name: "AXSwift", package: "AXSwift"),
            ],
            path: "Sources/MenuBarItemService"
        ),
    ]
)
EOF

# ---------------------------------------------------------------- resolve + strip previews
log "resolving dependencies"
(cd "$BUILD" && swift package resolve)

# #Preview blocks need Xcode's PreviewsMacros plugin; strip them from the
# staged sources and dependency checkouts (not needed in release builds).
log "stripping #Preview blocks"
chmod -R u+w "$BUILD/.build/checkouts" 2>/dev/null || true
find "$BUILD/Sources" -name "*.swift" -print0 |
    xargs -0 python3 "$ROOT/Scripts/clt-build-support/strip_previews.py" 2>/dev/null || true
find "$BUILD/.build/checkouts" -path "*/Sources/*" -name "*.swift" -print0 |
    xargs -0 python3 "$ROOT/Scripts/clt-build-support/strip_previews.py" 2>/dev/null || true

# ---------------------------------------------------------------- compile
log "compiling with SwiftPM (release)"
# -enable-bare-slash-regex: Xcode passes this for Swift 5 mode; SPM does not.
(cd "$BUILD" && swift build -c release -Xswiftc -enable-bare-slash-regex)
REL="$BUILD/.build/release"
[[ -x "$REL/IceApp" && -x "$REL/MenuBarItemService" ]] || die "build products missing"
cp "$BUILD/Package.resolved" "$STAGE/Package.resolved" 2>/dev/null || true

# ---------------------------------------------------------------- assets
log "fetching compiled asset catalog"
if [[ ! -f "$ASSETS_ZIP" ]]; then
    curl -fsSL -o "$ASSETS_ZIP" "$ASSETS_URL" || die "could not download asset archive from $ASSETS_URL"
fi
echo "$ASSETS_SHA256  $ASSETS_ZIP" | shasum -a 256 --check --quiet ||
    die "asset archive failed integrity check (expected SHA-256 $ASSETS_SHA256); delete $ASSETS_ZIP to re-download"
rm -rf "$STAGE/assets/extracted"
mkdir -p "$STAGE/assets/extracted"
ditto -x -k "$ASSETS_ZIP" "$STAGE/assets/extracted"
CAR=$(find "$STAGE/assets/extracted" -name "Assets.car" -maxdepth 4 | head -1)
[[ -n "$CAR" ]] || die "Assets.car not found in release archive"

log "generating app icon"
ICONSET="$STAGE/assets/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for png in "$ROOT"/Ice/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png; do
    base=${png:t}
    # icon_16x16@2x.png -> icon_16x16@2x.png (iconutil naming already matches)
    cp "$png" "$ICONSET/$base"
done
iconutil -c icns -o "$STAGE/assets/AppIcon.icns" "$ICONSET"

# ---------------------------------------------------------------- assemble
log "assembling Ice.app"
rm -rf "$OUT_APP"
CONT="$OUT_APP/Contents"
XPC="$CONT/XPCServices/MenuBarItemService.xpc"
mkdir -p "$CONT/MacOS" "$CONT/Frameworks" "$CONT/Resources" "$XPC/Contents/MacOS"

cp "$REL/IceApp" "$CONT/MacOS/Ice"
cp "$REL/MenuBarItemService" "$XPC/Contents/MacOS/MenuBarItemService"
cp "$CAR" "$CONT/Resources/Assets.car"
cp "$STAGE/assets/AppIcon.icns" "$CONT/Resources/AppIcon.icns"
for f in Acknowledgements.pdf Acknowledgements.rtf; do
    [[ -f "$ROOT/Ice/Resources/$f" ]] && cp "$ROOT/Ice/Resources/$f" "$CONT/Resources/"
done
# SwiftPM resource bundles (e.g. CompactSlider) that Xcode would put in Resources
for b in "$REL"/*.bundle; do
    [[ -d "$b" ]] && cp -R "$b" "$CONT/Resources/"
done
# Sparkle binary framework
SPARKLE=$(find "$BUILD/.build" -name "Sparkle.framework" -not -path "*checkouts*" | head -1)
[[ -n "$SPARKLE" ]] || die "Sparkle.framework not found in build output"
cp -R "$SPARKLE" "$CONT/Frameworks/Sparkle.framework"

cat > "$CONT/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>Ice</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.jordanbaird.Ice</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Ice</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$MARKETING_VERSION</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
	<key>CFBundleVersion</key>
	<string>$CURRENT_PROJECT_VERSION</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>Copyright © 2025 Jordan Baird</string>
	<key>SUFeedURL</key>
	<string>https://jordanbaird.github.io/ice-releases/appcast.xml</string>
	<key>SUPublicEDKey</key>
	<string>3nfIGMOD8DALPE8vIdFo2tUOIVc2MVbzhc+2J9JLn+Q=</string>
</dict>
</plist>
EOF

cat > "$XPC/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>MenuBarItemService</string>
	<key>CFBundleIdentifier</key>
	<string>com.jordanbaird.Ice.MenuBarItemService</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>MenuBarItemService</string>
	<key>CFBundlePackageType</key>
	<string>XPC!</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>XPCService</key>
	<dict>
		<key>JoinExistingSession</key>
		<true/>
		<key>RunLoopType</key>
		<string>NSRunLoop</string>
		<key>ServiceType</key>
		<string>Application</string>
	</dict>
</dict>
</plist>
EOF

printf 'APPL????' > "$CONT/PkgInfo"

# rpath for the embedded Sparkle framework
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONT/MacOS/Ice" 2>/dev/null || true

# ---------------------------------------------------------------- sign
log "signing (ad-hoc, hardened runtime)"
codesign --force --sign - --options runtime "$XPC"
codesign --force --sign - --options runtime "$OUT_APP"

log "done: $OUT_APP"
