#!/bin/bash

# Build script to compile mouselock in Release mode and optionally package as DMG
# 编译脚本：构建 MouseLock Release 版本，可选择打包成 DMG

set -e

echo "=========================================="
echo "Building MouseLock in Release mode..."
echo "=========================================="

# 获取版本标签或 commit id
VERSION=$(git describe HEAD 2>/dev/null || echo "v1.0.0")
echo "Version: $VERSION"

# 设置 app 版本
agvtool new-version ${VERSION:1}

# 构建应用
echo "Compiling..."
xcodebuild -quiet -scheme MouseLock -configuration Release -destination 'platform=macOS,arch=arm64' clean build

echo ""
echo "Copying built app to ./bin directory..."
rm -rf bin/MouseLock.app
mkdir -p bin

# 从 DerivedData 找到构建的 app
BUILT_APP="$(find ~/Library/Developer/Xcode/DerivedData -name "MouseLock.app" -path "*Release*" -type d 2>/dev/null | head -1)"

if [ -z "$BUILT_APP" ]; then
    echo "Error: Could not find built MouseLock.app"
    exit 1
fi

echo "Source: $BUILT_APP"
cp -r "$BUILT_APP" bin/

echo ""
echo "=========================================="
echo "✅ Build completed successfully!"
echo "=========================================="
echo "App location: ./bin/MouseLock.app"
ls -lh bin/MouseLock.app/Contents/MacOS/MouseLock

# 询问是否打包成 DMG
echo ""
read -p "Do you want to package as DMG? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "=========================================="
    echo "Creating DMG package..."
    echo "=========================================="
    
    # 清理并创建 dist 目录
    rm -rf dist && mkdir dist
    
    # 创建 DMG 文件
    echo "Generating DMG from ./bin/MouseLock.app..."
    hdiutil create -fs HFS+ -srcfolder bin/MouseLock.app -volname MouseLock dist/MouseLock-${VERSION:1}.dmg
    
    echo ""
    echo "=========================================="
    echo "✅ DMG package created successfully!"
    echo "=========================================="
    echo "DMG location: ./dist/MouseLock-${VERSION:1}.dmg"
    ls -lh dist/MouseLock-*.dmg
else
    echo "Skipping DMG package creation."
fi

echo ""
echo "Done!"
