#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# 1. Build tweak stage using logos and clang
echo "==> 1. Compiling dockpid (arm64e)..."
SDK_PATH=$(xcrun --show-sdk-path --sdk macosx)
SUPPORT_DIR="$DIR/../../XCode-projects/DYLIB/TI_Support"
if [ ! -d "$SUPPORT_DIR" ]; then
    SUPPORT_DIR="/Users/doraorak/Desktop/programming/XCode-projects/DYLIB/TI_Support"
fi

TWEAKINJECT_DIR="$DIR/../../XCode-projects/APP/My apps/TweakInject"
SUPPORT_LIB="/Library/TweakInject/TI_Support.dylib"
if [ ! -f "$SUPPORT_LIB" ]; then
    if [ -f "$TWEAKINJECT_DIR/Payload/TI_Support.dylib" ]; then
        SUPPORT_LIB="$TWEAKINJECT_DIR/Payload/TI_Support.dylib"
    elif [ -f "$SUPPORT_DIR/TI_Support.dylib" ]; then
        SUPPORT_LIB="$SUPPORT_DIR/TI_Support.dylib"
    elif [ -f "/Library/TweakInject/TI_PreferenceSupport.dylib" ]; then
        SUPPORT_LIB="/Library/TweakInject/TI_PreferenceSupport.dylib"
    fi
fi

"$THEOS/bin/logos.pl" "$DIR/Tweak.x" > "$DIR/Tweak.m"
clang -shared -arch arm64e -isysroot "$SDK_PATH" -fobjc-arc -fno-modules \
    -I"$SUPPORT_DIR" \
    -framework Foundation -framework AppKit -framework CoreFoundation \
    "$SUPPORT_LIB" \
    -install_name /Library/TweakInject/Tweaks/DynamicLibraries/dockpid.dylib \
    -x objective-c "$DIR/Tweak.m" \
    -o "$DIR/dockpid.dylib"
codesign -f -s - "$DIR/dockpid.dylib"
rm -f "$DIR/Tweak.m"

STAGE_DIR="$DIR/.stage"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/Library/TweakInject/Tweaks/DynamicLibraries"
mkdir -p "$STAGE_DIR/Library/TweakInject/Preferences/PreferenceBundles"

cp "$DIR/dockpid.dylib" "$STAGE_DIR/Library/TweakInject/Tweaks/DynamicLibraries/"
cp "$DIR/dockpid.plist" "$STAGE_DIR/Library/TweakInject/Tweaks/DynamicLibraries/"
if [ -d "$DIR/layout/Library/TweakInject/Preferences/PreferenceBundles/dockpidPrefs.bundle" ]; then
    cp -R "$DIR/layout/Library/TweakInject/Preferences/PreferenceBundles/dockpidPrefs.bundle" "$STAGE_DIR/Library/TweakInject/Preferences/PreferenceBundles/"
fi

# Version comes from ./control so the two cannot drift.
PKG_VERSION="$(awk '/^Version:/{print $2}' "$DIR/control")"
OUTPUT_DEB="$DIR/packages/com.doraorak.dockpid_${PKG_VERSION}_darwin-arm64e.deb"

echo "==> 2. Generating standard .deb package..."
python3 - "$STAGE_DIR" "$DIR/control" "$OUTPUT_DEB" << 'PYEOF'
import sys, os, tarfile, tempfile, shutil

stage_dir = sys.argv[1]
control_file = sys.argv[2]
output_deb = sys.argv[3]

def create_ar_header(filename, size):
    return (filename.ljust(16) + "0".ljust(12) + "0".ljust(6) + "0".ljust(6) + "100644".ljust(8) + str(size).ljust(10) + "`\n").encode('ascii')

temp_dir = tempfile.mkdtemp()
try:
    deb_bin = b"2.0\n"
    control_tar = os.path.join(temp_dir, "control.tar.gz")
    with tarfile.open(control_tar, "w:gz") as tar:
        tar.add(control_file, arcname="./control")
    with open(control_tar, "rb") as f:
        c_data = f.read()

    data_tar = os.path.join(temp_dir, "data.tar.gz")
    with tarfile.open(data_tar, "w:gz") as tar:
        for item in sorted(os.listdir(stage_dir)):
            tar.add(os.path.join(stage_dir, item), arcname=f"./{item}")
    with open(data_tar, "rb") as f:
        d_data = f.read()

    os.makedirs(os.path.dirname(os.path.abspath(output_deb)), exist_ok=True)
    with open(output_deb, "wb") as deb:
        deb.write(b"!<arch>\n")
        deb.write(create_ar_header("debian-binary", len(deb_bin)))
        deb.write(deb_bin + (b"\n" if len(deb_bin) % 2 else b""))
        deb.write(create_ar_header("control.tar.gz", len(c_data)))
        deb.write(c_data + (b"\n" if len(c_data) % 2 else b""))
        deb.write(create_ar_header("data.tar.gz", len(d_data)))
        deb.write(d_data + (b"\n" if len(d_data) % 2 else b""))
finally:
    shutil.rmtree(temp_dir)
print(f"Created: {output_deb}")
PYEOF

echo "==> Done! Output: $OUTPUT_DEB"
