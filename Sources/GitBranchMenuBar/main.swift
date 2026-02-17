import AppKit
import ServiceManagement

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()

struct LaunchAtLoginManager {
    @available(macOS 13.0, *)
    static func isEnabled() -> Bool {
        if case .enabled = SMAppService.mainApp.status {
            return true
        }
        return false
    }

    @available(macOS 13.0, *)
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var refreshTimer: Timer?
    private let gitService = GitBranchService()
    private let defaults = UserDefaults.standard
    private let repoPathKey = "GitBranchMenuBar.selectedRepoPath"
    private let refreshInterval: TimeInterval = 5
    private let maxStatusLength = 28

    private var repositoryURL: URL?
    private var repoPathMenuItem: NSMenuItem?
    private var statusMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        restoreRepositoryFromUserDefaults()
        startRefreshTimer()
        updateBranchDisplay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    private func setupMenu() {
        updateStatusTitle("No repo selected")

        let selectRepoItem = NSMenuItem(title: "リポジトリを選択...", action: #selector(selectRepository), keyEquivalent: "s")
        selectRepoItem.target = self
        menu.addItem(selectRepoItem)

        let clearRepoItem = NSMenuItem(title: "選択を解除", action: #selector(clearRepository), keyEquivalent: "d")
        clearRepoItem.target = self
        menu.addItem(clearRepoItem)

        let launchAtLoginItem = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "l")
        launchAtLoginItem.target = self
        launchAtLoginMenuItem = launchAtLoginItem
        menu.addItem(launchAtLoginItem)

        updateLaunchAtLoginMenuItemState()

        menu.addItem(.separator())

        repoPathMenuItem = NSMenuItem(title: "リポジトリ 未選択", action: nil, keyEquivalent: "")
        repoPathMenuItem?.isEnabled = false
        if let repoPathMenuItem {
            menu.addItem(repoPathMenuItem)
        }

        statusMenuItem = NSMenuItem(title: "ブランチ -", action: nil, keyEquivalent: "")
        statusMenuItem?.isEnabled = false
        if let statusMenuItem {
            menu.addItem(statusMenuItem)
        }

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "更新", action: #selector(updateBranchDisplay), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let openItem = NSMenuItem(title: "リポジトリを開く", action: #selector(openRepositoryInFinder), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "終了", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func restoreRepositoryFromUserDefaults() {
        guard let path = defaults.string(forKey: repoPathKey) else {
            return
        }

        let url = URL(fileURLWithPath: path)
        guard gitService.isGitRepository(at: url) else {
            defaults.removeObject(forKey: repoPathKey)
            return
        }

        setRepository(url, shouldPersist: false)
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.updateBranchDisplay()
        }
    }

    private func setRepository(_ url: URL, shouldPersist: Bool = true) {
        repositoryURL = url

        if shouldPersist {
            defaults.set(url.path, forKey: repoPathKey)
        }

        repoPathMenuItem?.title = "リポジトリ \(url.lastPathComponent)"
        statusMenuItem?.title = "ブランチ 更新中"
        statusItem.button?.appearsDisabled = false
        updateBranchDisplay()
    }

    private func updateStatusTitle(_ text: String) {
        let displayText: String
        if repositoryURL == nil {
            displayText = text
        } else if text.hasPrefix("No ") || text == "Unavailable" {
            displayText = text
        } else {
            let repoName = repositoryURL?.lastPathComponent ?? "repo"
            displayText = "\(repoName) → \(text)"
        }

        statusItem.button?.title = shorten(displayText, max: maxStatusLength)
        statusMenuItem?.title = "ブランチ \(text)"
    }

    private func updateLaunchAtLoginMenuItemState() {
        guard let launchAtLoginMenuItem else {
            return
        }

        if #available(macOS 13.0, *) {
            launchAtLoginMenuItem.title = "ログイン時に起動"
            launchAtLoginMenuItem.isEnabled = true
            launchAtLoginMenuItem.state = LaunchAtLoginManager.isEnabled() ? .on : .off
        } else {
            launchAtLoginMenuItem.title = "ログイン時に起動 (macOS 13+)"
            launchAtLoginMenuItem.isEnabled = false
            launchAtLoginMenuItem.state = .off
        }
    }

    @objc private func selectRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        panel.message = "Gitリポジトリのフォルダを選択してください"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        guard gitService.isGitRepository(at: url) else {
            showError("選択したフォルダはGitリポジトリではありません。")
            return
        }

        setRepository(url)
    }

    @objc private func clearRepository() {
        repositoryURL = nil
        defaults.removeObject(forKey: repoPathKey)
        repoPathMenuItem?.title = "リポジトリ 未選択"
        statusItem.button?.appearsDisabled = false
        updateStatusTitle("No repo selected")
    }

    @objc private func openRepositoryInFinder() {
        guard let repositoryURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([repositoryURL])
    }

    @objc private func updateBranchDisplay() {
        guard let repositoryURL else {
            updateStatusTitle("No repo selected")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else {
                return
            }

            do {
                let branch = try self.gitService.currentBranchDisplay(at: repositoryURL)
                DispatchQueue.main.async {
                    self.updateStatusTitle(branch)
                }
            } catch {
                DispatchQueue.main.async {
                    self.updateStatusTitle("Unavailable")
                }
            }
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        guard #available(macOS 13.0, *) else {
            return
        }

        let shouldEnable = sender.state == .off
        do {
            try LaunchAtLoginManager.setEnabled(shouldEnable)
            updateLaunchAtLoginMenuItemState()
        } catch {
            showError("ログイン時起動の設定に失敗しました。\n\(error.localizedDescription)")
            updateLaunchAtLoginMenuItemState()
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Git リポジトリの選択に失敗"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func shorten(_ text: String, max: Int) -> String {
        if text.count <= max {
            return text
        }

        return String(text.prefix(max - 1)) + "…"
    }
}
