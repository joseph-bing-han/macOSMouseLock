# mouselock 项目开发指南

## 项目概述

**mouselock** 是一个轻量级 macOS 菜单栏应用程序，可以将鼠标光标限制在指定的显示器范围内。用户可以通过菜单栏选择要锁定的显示器，支持多显示器场景。

## 技术栈

- **语言**：Swift 5+
- **框架**：SwiftUI + AppKit
- **目标系统**：macOS 12.0+
- **依赖库**：
  - `LaunchAtLogin` - 实现开机启动功能
  - AppKit 原生框架 - 全局事件监听与鼠标控制

## 项目结构

```
mouselock/
├── MouseLockApp.swift       # 主应用入口与业务逻辑
├── mouselock.entitlements   # macOS 权限配置
└── Assets.xcassets/         # 图标与资源文件

mouselock.xcodeproj/         # Xcode 项目配置
```

## 核心实现原理

### 应用架构
- **AppDelegate**：实现 `ObservableObject` 协议，管理应用状态和鼠标锁定逻辑
- **MouseLockMenuView**：SwiftUI 视图，提供用户交互界面
- **DisplayInfo**：数据模型，表示单个显示器的信息

### 鼠标锁定机制
1. **显示器枚举**：启动时使用 `NSScreen.screens` 获取所有连接的显示器
2. **用户选择**：通过菜单栏让用户选择目标显示器（默认主屏幕）
3. **事件监听**：启用锁定后，使用 `NSEvent.addGlobalMonitorForEvents` 捕获全局鼠标事件
4. **坐标限制**：计算鼠标实际位置相对于目标屏幕的坐标，通过 `CGWarpMouseCursorPosition` 进行约束

## 开发规范

### 代码风格
- 代码注释必须使用中文
- 字符串、常量、类名、方法名使用英文
- 按照 Swift 风格指南组织代码（使用 MARK:）

### 修改建议
- **UI 修改**：在 `MouseLockMenuView` 中添加更多菜单项或设置选项
- **业务逻辑修改**：编辑 `AppDelegate` 类中的 `startLocking()` 和 `stopLocking()` 方法
- **显示器信息**：修改 `updateDisplayList()` 中的显示器名称格式或添加其他信息

### 权限要求
应用需要以下权限才能正常工作：
- **全局事件监听**：获取 `NSEvent.addGlobalMonitorForEvents` 的权限（用户需在系统偏好设置中手动授予）
- **鼠标控制**：通过 `CGWarpMouseCursorPosition` 控制鼠标位置

## 构建与运行

### Xcode 构建
```bash
# 使用 Xcode 打开项目
open mouselock.xcodeproj

# 或使用命令行构建
xcodebuild -scheme mouselock -configuration Release
```

### 测试步骤
1. 构建并运行应用（Cmd+R）
2. 启动英雄联盟
3. 验证鼠标光标被限制在游戏窗口所在屏幕内
4. 测试多屏场景：移动鼠标到另一屏幕，确认光标回弹

## 菜单栏功能说明

### 启用鼠标锁定 (Toggle)
- 打开/关闭鼠标锁定功能
- 当启用时，鼠标光标被限制在选定显示器内

### 显示器选择 (Menu)
- 显示当前连接的所有显示器列表
- 列表中显示显示器名称和分辨率
- 选中项标记有 ✓ 符号
- 点击选择不同显示器后，会自动重启锁定

### 开机启动 (Toggle)
- 控制应用是否随系统启动
- 基于 LaunchAtLogin 库实现

### 退出
- 关闭应用并停止所有鼠标锁定

## 已知问题与限制

- 首次使用需要在系统偏好设置中手动授予全局事件监听权限
- 锁定范围限制为显示器边界内 1 像素处（防止光标完全卡死）
- 当显示器断开连接时，需要重新选择显示器

## 常见修改场景

### 调整鼠标限制边距
修改 `startLocking()` 中的坐标计算：
```swift
minValue: screenFrame.minX + 1  // 修改边界偏移值
maxValue: screenFrame.maxX - 1
```

### 添加显示器自动检测
在 `updateDisplayList()` 中添加监听显示器连接/断开事件：
```swift
let center = NSWorkspace.shared.notificationCenter
center.addObserver(self, selector: #selector(screensDidChange),
                   name: NSApplication.didChangeScreenParametersNotification, object: nil)
```

### 自定义显示器名称格式
修改 `updateDisplayList()` 中的名称生成方式：
```swift
name: "Display \(index): \(displayName)"  // 添加索引号
```

## 调试技巧

- 添加 `print()` 语句在事件处理方法中跟踪鼠标事件
- 使用 Xcode 的 Console 输出进行调试
- 在 `AppDelegate` 中的关键方法添加日志验证游戏检测逻辑
