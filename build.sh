#!/bin/bash

# Build script to compile mouselock in Release mode and copy to ./bin directory

set -e

echo "Building MouseLock in Release mode..."
xcodebuild -scheme MouseLock -configuration Release clean build

echo "Copying built app to ./bin directory..."
rm -rf bin/MouseLock.app
mkdir -p bin

# Find the built app and copy it
BUILT_APP="$(find ~/Library/Developer/Xcode/DerivedData -name "MouseLock.app" -path "*Release*" -type d 2>/dev/null | head -1)"

if [ -z "$BUILT_APP" ]; then
    echo "Error: Could not find built MouseLock.app"
    exit 1
fi

echo "Source: $BUILT_APP"
cp -r "$BUILT_APP" bin/

echo "Done! Release app is available at: ./bin/MouseLock.app"
ls -lh bin/MouseLock.app/Contents/MacOS/MouseLock
