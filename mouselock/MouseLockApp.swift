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
                .onChange(of: delegate.isLocking) { newValue in
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
    
    private var lockTimer: Timer?
    private var lockBounds: CGRect = .zero
    private var lastCheckTime: TimeInterval = 0
    
    // 优化：缓存屏幕高度和边界值，避免每次计算
    private var cachedScreenHeight: CGFloat = 0
    private var cachedMinX: CGFloat = 0
    private var cachedMaxX: CGFloat = 0
    private var cachedMinY: CGFloat = 0
    private var cachedMaxY: CGFloat = 0
    
    // 记录上次鼠标位置，用于判断移动方向
    private var lastMousePosition: CGPoint = .zero
    
    var selectedDisplayName: String {
        displayList.first(where: { $0.id == selectedDisplayID })?.name ?? "主屏幕"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateDisplayList()
        // 获取主屏幕的 displayID
        if let mainScreen = NSScreen.main,
           let displayID = mainScreen.displayID {
            selectedDisplayID = displayID
        } else if let firstDisplay = displayList.first {
            selectedDisplayID = firstDisplay.id
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
        stopLocking()
        
        // 获取显示器边界
        lockBounds = CGDisplayBounds(selectedDisplayID)
        
        // 优化：预先计算并缓存所有需要的值
        cachedScreenHeight = NSScreen.screens.reduce(0) { max($0, $1.frame.maxY) }
        
        let margin: CGFloat = 2.0
        cachedMinX = lockBounds.minX + margin
        cachedMaxX = lockBounds.maxX - margin
        cachedMinY = lockBounds.minY + margin
        cachedMaxY = lockBounds.maxY - margin
        
        // 优化：降低检查频率到 10ms，既能保持流畅又减少 CPU 负载
        lockTimer = Timer.scheduledTimer(withTimeInterval: 0.010, repeats: true) { [weak self] _ in
            self?.checkAndConstrainMouse()
        }
        
        // 确保定时器在所有 RunLoop 模式下运行
        if let timer = lockTimer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    func stopLocking() {
        lockTimer?.invalidate()
        lockTimer = nil
        lastCheckTime = 0
        lastMousePosition = .zero
    }
    
    // 检查并约束鼠标位置
    private func checkAndConstrainMouse() {
        // 获取当前鼠标位置
        let mouseLocation = NSEvent.mouseLocation
        
        // 优化：使用缓存的屏幕高度，避免每次遍历所有屏幕
        let cgPoint = CGPoint(x: mouseLocation.x, y: cachedScreenHeight - mouseLocation.y)
        
        // 检查鼠标是否在边界范围内
        let isInBounds = cgPoint.x >= cachedMinX && cgPoint.x <= cachedMaxX &&
                         cgPoint.y >= cachedMinY && cgPoint.y <= cachedMaxY
        
        // 如果鼠标在边界内，只需更新位置记录，不做任何限制
        if isInBounds {
            lastMousePosition = cgPoint
            return
        }
        
        // 鼠标超出边界，需要进行约束
        let currentTime = Date().timeIntervalSince1970
        
        // 优化防抖：缩短间隔到 5ms，避免边界卡顿
        guard currentTime - lastCheckTime >= 0.005 else { return }
        
        // 计算约束后的位置
        var constrainedX = cgPoint.x
        var constrainedY = cgPoint.y
        
        // X 轴约束
        if cgPoint.x < cachedMinX {
            constrainedX = cachedMinX
        } else if cgPoint.x > cachedMaxX {
            constrainedX = cachedMaxX
        }
        
        // Y 轴约束
        if cgPoint.y < cachedMinY {
            constrainedY = cachedMinY
        } else if cgPoint.y > cachedMaxY {
            constrainedY = cachedMaxY
        }
        
        // 执行 warp
        let constrainedPoint = CGPoint(x: constrainedX, y: constrainedY)
        CGWarpMouseCursorPosition(constrainedPoint)
        
        lastCheckTime = currentTime
        lastMousePosition = constrainedPoint
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


