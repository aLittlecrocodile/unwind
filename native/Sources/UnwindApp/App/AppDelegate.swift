import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = AppStore.shared
    private lazy var pet = PetWindowController(store: store)
    private lazy var workbench = WorkbenchWindowController(store: store)
    private lazy var unwind = UnwindWindowController()
    private var hideTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureMenu()
        bindWindows()
        requestNotificationPermission()
        pet.positionAtBottomRight()
        pet.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        if CommandLine.arguments.contains("--show-workbench") {
            pet.window?.orderOut(nil)
            workbench.showWindow(nil)
            workbench.window?.center()
        } else if CommandLine.arguments.contains("--show-unwind") {
            pet.window?.orderOut(nil)
            showUnwind()
        }

        store.onFocusCompleted = { [weak self] in
            self?.notify(title: "该休息了", body: "这轮打完了，小人想陪你喘口气。")
        }
        store.onBreakCompleted = { [weak self] in
            self?.notify(title: "休息结束", body: "准备好时，再开始下一轮。")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPet()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === workbench.window { showPet() }
    }

    private func bindWindows() {
        workbench.window?.delegate = self
        pet.onOpenWorkbench = { [weak self] in
            guard let self else { return }
            pet.window?.orderOut(nil)
            workbench.showWindow(nil)
            workbench.window?.center()
            NSApp.activate(ignoringOtherApps: true)
        }
        pet.onOpenUnwind = { [weak self] in self?.showUnwind() }
        pet.onHideTemporarily = { [weak self] in self?.hidePetTemporarily() }
        workbench.onReturnToPet = { [weak self] in
            self?.workbench.close()
            self?.showPet()
        }
        workbench.onOpenUnwind = { [weak self] in self?.showUnwind() }
    }

    private func showUnwind() {
        unwind.showWindow(nil)
        unwind.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showPet() {
        hideTask?.cancel(); hideTask = nil
        pet.showWindow(nil)
        pet.window?.ignoresMouseEvents = false
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hidePetTemporarily() {
        pet.window?.orderOut(nil)
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled else { return }
            self?.showPet()
        }
    }

    private func requestNotificationPermission() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func configureMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Unwind", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Unwind", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }
}
