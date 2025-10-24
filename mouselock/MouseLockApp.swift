import AppKit
import SwiftUI
import LaunchAtLogin
import CoreGraphics

@main
struct MouseLockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("Mouse Lock", systemImage: "computermouse") {
            MouseLockMenuView(delegate: delegate)
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - Menu View
struct MouseLockMenuView: View {
    @ObservedObject var delegate: AppDelegate
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 锁定开关
            Toggle("启用鼠标锁定", isOn: $delegate.isLocking)
                .onChange(of: delegate.isLocking) { oldValue, newValue in
                    if newValue {
                        delegate.startLocking()
                    } else {
                        delegate.stopLocking()
                    }
                }
            
            Divider()
            
            // 显示器选择菜单
            Menu {
                ForEach(delegate.displayList, id: \.self) { display in
                    Button(action: {
                        delegate.selectedDisplayID = display.id
                        delegate.isLocking = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            delegate.isLocking = true
                        }
                    }) {
                        HStack {
                            if display.id == delegate.selectedDisplayID {
                                Image(systemName: "checkmark")
                            }
                            Text(display.name)
                        }
                    }
                }
            } label: {
                HStack {
                    Text("显示器:")
                    Text(delegate.selectedDisplayName).fontWeight(.semibold)
                }
            }
            
            Divider()
            
            Toggle("开机启动", isOn: Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.isEnabled = $0 }
            ))
            
            Divider()
            
            Button("退出") { NSApp.terminate(nil) }
        }
        .padding(12)
        .frame(minWidth: 220)
    }
}

// MARK: - Display Model
struct DisplayInfo: Hashable {
    let id: CGDirectDisplayID
    let name: String
    let frame: NSRect
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: DisplayInfo, rhs: DisplayInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - App Delegate
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published var isLocking = false
    @Published var selectedDisplayID: CGDirectDisplayID = 0
    @Published var displayList: [DisplayInfo] = []
    
    private var eventMonitor: Any?
    private var lockBounds: CGRect = .zero
    private var hasWarped: Bool = false  // 标记是否已经执行过 warp
    
    // 优化：缓存屏幕高度和边界值，避免每次计算
    private var cachedScreenHeight: CGFloat = 0
    private var cachedMinX: CGFloat = 0
    private var cachedMaxX: CGFloat = 0
    private var cachedMinY: CGFloat = 0
    private var cachedMaxY: CGFloat = 0
    
    // 回拉距离：当鼠标超出边界时，拉回到距离边界这个距离的位置
    private let pullbackDistanceX: CGFloat = 20.0  // 左右
    private let pullbackDistanceY: CGFloat = 5.0   // 上下
    
    // 安全区域：鼠标回到这个区域内才重置 warp 状态
    private let safeZone: CGFloat = 10.0
    
    var selectedDisplayName: String {
        displayList.first(where: { $0.id == selectedDisplayID })?.name ?? "主屏幕"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 检查辅助功能权限
        checkAccessibilityPermission()
        
        updateDisplayList()
        // 获取主屏幕的 displayID
        if let mainScreen = NSScreen.main,
           let displayID = mainScreen.displayID {
            selectedDisplayID = displayID
        } else if let firstDisplay = displayList.first {
            selectedDisplayID = firstDisplay.id
        }
    }
    
    // MARK: - Permission Check
    /// 检查并请求辅助功能权限
    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let hasPermission = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !hasPermission {
            // 显示提示对话框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let alert = NSAlert()
                alert.messageText = "需要辅助功能权限"
                alert.informativeText = """
                MouseLock 需要辅助功能权限才能锁定鼠标。
                
                请按照以下步骤操作：
                1. 打开"系统设置"
                2. 进入"隐私与安全性" > "辅助功能"
                3. 将 MouseLock 添加到允许列表
                4. 重新启动应用
                """
                alert.alertStyle = .warning
                alert.addButton(withTitle: "打开系统设置")
                alert.addButton(withTitle: "稍后设置")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // 打开系统设置的辅助功能页面
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }


    func applicationWillTerminate(_ notification: Notification) {
        stopLocking()
    }

    // MARK: - Display Management
    private func updateDisplayList() {
        let list = NSScreen.screens.compactMap { screen -> DisplayInfo? in
            guard let displayID = screen.displayID else { return nil }
            let displayName = screen.localizedName
            return DisplayInfo(
                id: displayID,
                name: "\(displayName) (\(Int(screen.frame.width))x\(Int(screen.frame.height)))",
                frame: screen.frame
            )
        }
        
        DispatchQueue.main.async {
            self.displayList = list
        }
    }

    // MARK: - Mouse Lock Logic
    func startLocking() {
        // 检查辅助功能权限
        let hasPermission = AXIsProcessTrusted()
        if !hasPermission {
            // 如果没有权限，显示提示并停止
            DispatchQueue.main.async { [weak self] in
                self?.isLocking = false
                let alert = NSAlert()
                alert.messageText = "缺少辅助功能权限"
                alert.informativeText = "请在系统设置中授予 MouseLock 辅助功能权限后再试。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "打开系统设置")
                alert.addButton(withTitle: "取消")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }
        
        stopLocking()
        
        // 获取显示器边界
        lockBounds = CGDisplayBounds(selectedDisplayID)
        
        // 优化：预先计算并缓存所有需要的值
        cachedScreenHeight = NSScreen.screens.reduce(0) { max($0, $1.frame.maxY) }
        
        // 边界：留出最小安全距离
        let margin: CGFloat = 3.0
        cachedMinX = lockBounds.minX + margin
        cachedMaxX = lockBounds.maxX - margin
        cachedMinY = lockBounds.minY + margin
        cachedMaxY = lockBounds.maxY - margin
        
        // 重置状态
        hasWarped = false
        
        // 使用全局事件监听，只在鼠标移动时检测
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            self?.checkAndConstrainMouse()
        }
    }

    func stopLocking() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        hasWarped = false
    }
    
    // 检查并约束鼠标位置
    private func checkAndConstrainMouse() {
        // 获取当前鼠标位置
        let mouseLocation = NSEvent.mouseLocation
        
        // 转换为 CG 坐标系（Y 轴反转）
        let cgPoint = CGPoint(x: mouseLocation.x, y: cachedScreenHeight - mouseLocation.y)
        
        // 计算鼠标到各边界的距离
        let distanceToLeft = cgPoint.x - cachedMinX
        let distanceToRight = cachedMaxX - cgPoint.x
        let distanceToTop = cgPoint.y - cachedMinY
        let distanceToBottom = cachedMaxY - cgPoint.y
        
        // 检查鼠标是否在安全区域内（距离所有边界都超过 safeZone）
        let isInSafeZone = distanceToLeft >= safeZone && 
                          distanceToRight >= safeZone &&
                          distanceToTop >= safeZone && 
                          distanceToBottom >= safeZone
        
        // 如果在安全区域内，重置 warp 状态，允许下次拉回
        if isInSafeZone {
            hasWarped = false
            return
        }
        
        // 检查鼠标是否超出边界
        let isOutOfBounds = cgPoint.x < cachedMinX || cgPoint.x > cachedMaxX ||
                           cgPoint.y < cachedMinY || cgPoint.y > cachedMaxY
        
        // 如果鼠标超出边界，且尚未执行过 warp，则拉回
        if isOutOfBounds && !hasWarped {
            var constrainedX = cgPoint.x
            var constrainedY = cgPoint.y
            
            // X 轴约束：如果超出边界，拉回到安全距离内
            if cgPoint.x < cachedMinX {
                constrainedX = cachedMinX + pullbackDistanceX
            } else if cgPoint.x > cachedMaxX {
                constrainedX = cachedMaxX - pullbackDistanceX
            }
            
            // Y 轴约束：如果超出边界，拉回到安全距离内
            if cgPoint.y < cachedMinY {
                constrainedY = cachedMinY + pullbackDistanceY
            } else if cgPoint.y > cachedMaxY {
                constrainedY = cachedMaxY - pullbackDistanceY
            }
            
            // 执行 warp，将鼠标拉回安全位置
            let constrainedPoint = CGPoint(x: constrainedX, y: constrainedY)
            CGWarpMouseCursorPosition(constrainedPoint)
            
            // 标记已经执行过 warp，防止重复拉回
            hasWarped = true
        }
    }
}

// MARK: - Helpers
private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let screenNumber = self.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}


