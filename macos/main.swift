import Cocoa
import Foundation

struct AppConfig: Codable {
    var threshold: String = "1GB"
    var interval: Double = 15.0
    var cooldown: Double = 300.0
    var sound: Bool = true
    var notifications_enabled: Bool = true
    var lang: String = "auto"
}

struct ProcessEntry {
    let pid: Int
    let name: String
    let rssBytes: Double
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var statusMenu: NSMenu!
    var timer: Timer?

    var config = AppConfig()
    var activeLang: String = "en"
    var notifiedAt: [Int: TimeInterval] = [:]
    var lastTopProcs: [ProcessEntry] = []
    var lastUpdatedStr: String = ""

    var topHeaderItem: NSMenuItem?
    var topProcessItems: [NSMenuItem] = []

    let thresholdOptions = ["500MB", "1GB", "1.5GB", "2GB", "3GB", "4GB"]
    let intervalOptions: [Double] = [2, 5, 10, 15, 30, 60]

    var configFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/memory-warning/config.json")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        loadConfig()
        resolveLanguage()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "💾"
        }

        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem.menu = statusMenu

        rebuildMenu()
        checkMemory()
        startTimer(interval: config.interval)
    }

    // MARK: - Config Persistence

    func loadConfig() {
        let url = configFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let t = json["threshold"] as? String { config.threshold = t }
                if let i = json["interval"] as? Double { config.interval = i }
                else if let iInt = json["interval"] as? Int { config.interval = Double(iInt) }
                if let c = json["cooldown"] as? Double { config.cooldown = c }
                else if let cInt = json["cooldown"] as? Int { config.cooldown = Double(cInt) }
                if let s = json["sound"] as? Bool { config.sound = s }
                if let n = json["notifications_enabled"] as? Bool { config.notifications_enabled = n }
                if let l = json["lang"] as? String { config.lang = l }
            }
        } catch {
            // Keep defaults on error
        }
    }

    func saveConfig() {
        let url = configFileURL
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dict: [String: Any] = [
                "threshold": config.threshold,
                "interval": Int(config.interval),
                "cooldown": Int(config.cooldown),
                "sound": config.sound,
                "notifications_enabled": config.notifications_enabled,
                "lang": config.lang
            ]
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
            try data.write(to: url)
        } catch {
            fputs("[ERROR] Failed to save config: \(error)\n", stderr)
        }
    }

    // MARK: - Localization

    func detectSystemLanguage() -> String {
        if let preferred = Locale.preferredLanguages.first?.lowercased() {
            if preferred.hasPrefix("ru") {
                return "ru"
            }
        }
        if let envLang = ProcessInfo.processInfo.environment["LANG"]?.lowercased(), envLang.hasPrefix("ru") {
            return "ru"
        }
        return "en"
    }

    func resolveLanguage() {
        if config.lang == "auto" {
            activeLang = detectSystemLanguage()
        } else {
            activeLang = (config.lang == "ru") ? "ru" : "en"
        }
    }

    var isRu: Bool {
        return activeLang == "ru"
    }

    // MARK: - Size Parsing & Formatting

    func parseSize(_ sizeStr: String) -> Double? {
        let cleaned = sizeStr.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pattern = #"^([0-9]+(?:\.[0-9]+)?)\s*([KMGTP]?B?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let valRange = Range(match.range(at: 1), in: cleaned),
              let unitRange = Range(match.range(at: 2), in: cleaned),
              let val = Double(cleaned[valRange]) else {
            return nil
        }

        let unit = String(cleaned[unitRange])
        let multipliers: [String: Double] = [
            "": 1,
            "B": 1,
            "K": 1024,
            "KB": 1024,
            "M": pow(1024, 2),
            "MB": pow(1024, 2),
            "G": pow(1024, 3),
            "GB": pow(1024, 3),
            "T": pow(1024, 4),
            "TB": pow(1024, 4)
        ]
        let mult = multipliers[unit] ?? pow(1024, 2)
        return val * mult
    }

    func formatBytes(_ bytes: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = bytes
        var unitIndex = 0
        while abs(value) >= 1024.0 && unitIndex < units.count - 1 {
            value /= 1024.0
            unitIndex += 1
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }

    // MARK: - Timer Management

    func startTimer(interval: Double) {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: interval, target: self, selector: #selector(onTimerTick), userInfo: nil, repeats: true)
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    @objc func onTimerTick() {
        checkMemory()
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Refresh immediately whenever the user clicks the menu bar icon
        checkMemory()
    }

    // MARK: - Process Scanning

    func extractDisplayName(from commPath: String) -> String {
        let components = commPath.split(separator: "/")
        // Prefer the top-level .app bundle name (e.g. "Antigravity IDE.app" instead of "Electron")
        for comp in components {
            if comp.lowercased().hasSuffix(".app") {
                return String(comp)
            }
        }
        return URL(fileURLWithPath: commPath).lastPathComponent
    }

    func parsePsLine(_ line: Substring) -> ProcessEntry? {
        var i = line.startIndex

        // 1. Skip leading whitespace
        while i < line.endIndex && line[i].isWhitespace {
            i = line.index(after: i)
        }
        let pidStart = i
        while i < line.endIndex && !line[i].isWhitespace {
            i = line.index(after: i)
        }
        guard pidStart < i, let pid = Int(line[pidStart..<i]) else { return nil }

        // 2. Skip whitespace between pid and rss
        while i < line.endIndex && line[i].isWhitespace {
            i = line.index(after: i)
        }
        let rssStart = i
        while i < line.endIndex && !line[i].isWhitespace {
            i = line.index(after: i)
        }
        guard rssStart < i, let rssKB = Double(line[rssStart..<i]) else { return nil }

        // 3. Skip whitespace before command path
        while i < line.endIndex && line[i].isWhitespace {
            i = line.index(after: i)
        }
        guard i < line.endIndex else { return nil }

        let commPath = String(line[i..<line.endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commPath.isEmpty else { return nil }

        let name = extractDisplayName(from: commPath)
        return ProcessEntry(pid: pid, name: name, rssBytes: rssKB * 1024.0)
    }

    func scanProcesses() -> [ProcessEntry] {
        var results: [ProcessEntry] = []
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ax", "-o", "pid=,rss=,comm="]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            if let output = String(data: data, encoding: .utf8) {
                for line in output.split(separator: "\n") {
                    if let entry = parsePsLine(line) {
                        results.append(entry)
                    }
                }
            }
        } catch {
            fputs("[ERROR] Failed to scan processes: \(error)\n", stderr)
        }
        return results
    }

    // MARK: - Memory Check & Alerting

    func checkMemory() {
        let thresholdBytes = parseSize(config.threshold) ?? pow(1024, 3)
        var allProcs = scanProcesses()
        let now = Date().timeIntervalSince1970

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        lastUpdatedStr = formatter.string(from: Date())

        // Clean up dead PIDs
        let livePids = Set(allProcs.map { $0.pid })
        for pid in Array(notifiedAt.keys) {
            if !livePids.contains(pid) {
                notifiedAt.removeValue(forKey: pid)
            }
        }

        // Sort descending by memory
        allProcs.sort { $0.rssBytes > $1.rssBytes }
        lastTopProcs = Array(allProcs.prefix(5))

        updateTopProcessesUI()

        let violators = allProcs.filter { $0.rssBytes >= thresholdBytes }

        if let topViolator = violators.first {
            statusItem.button?.title = "⚠️ \(formatBytes(topViolator.rssBytes))"
        } else {
            statusItem.button?.title = "💾"
        }

        guard config.notifications_enabled else { return }

        for proc in violators {
            let lastTime = notifiedAt[proc.pid] ?? 0
            if now - lastTime >= config.cooldown {
                notifiedAt[proc.pid] = now
                let memStr = formatBytes(proc.rssBytes)
                let threshStr = formatBytes(thresholdBytes)

                let title = isRu ? "Предупреждение о памяти" : "High Memory Warning"
                let subtitle = "\(proc.name) (PID: \(proc.pid))"
                let body = isRu
                    ? "Использование памяти: \(memStr) (Лимит: \(threshStr))"
                    : "Memory usage: \(memStr) (Limit: \(threshStr))"

                sendNotification(title: title, subtitle: subtitle, message: body, sound: config.sound)
            }
        }
    }

    func sendNotification(title: String, subtitle: String, message: String, sound: Bool) {
        if sound {
            NSSound(named: NSSound.Name("Ping"))?.play()
        }

        func escapeAS(_ s: String) -> String {
            return s.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
        }

        let soundClause = sound ? " sound name \"Ping\"" : ""
        let script = "display notification \"\(escapeAS(message))\" with title \"\(escapeAS(title))\" subtitle \"\(escapeAS(subtitle))\"\(soundClause)"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    // MARK: - Menu Construction & Updates

    func rebuildMenu() {
        statusMenu.removeAllItems()

        // 1. Top Memory Consumers Header
        let headerTitle = isRu ? "📊 Топ процессов по памяти:" : "📊 Top Memory Consumers:"
        let headerItem = NSMenuItem(title: headerTitle, action: #selector(onManualRefresh), keyEquivalent: "")
        headerItem.target = self
        statusMenu.addItem(headerItem)
        topHeaderItem = headerItem

        topProcessItems.removeAll()
        for i in 0..<5 {
            let placeholder = isRu ? "  #\(i + 1): сканирование..." : "  #\(i + 1): scanning..."
            let item = NSMenuItem(title: placeholder, action: #selector(openActivityMonitor), keyEquivalent: "")
            item.target = self
            statusMenu.addItem(item)
            topProcessItems.append(item)
        }

        updateTopProcessesUI()

        statusMenu.addItem(NSMenuItem.separator())

        // 2. Current Threshold & Interval Info
        let secInt = Int(config.interval)
        let statusTitle = isRu
            ? "⚡ Порог: \(config.threshold) (интервал: \(secInt)с)"
            : "⚡ Threshold: \(config.threshold) (every \(secInt)s)"
        let statusInfoItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusInfoItem.isEnabled = false
        statusMenu.addItem(statusInfoItem)

        // 3. Change Threshold Submenu
        let threshMenuTitle = isRu ? "Изменить порог" : "Change Threshold"
        let threshMenuItem = NSMenuItem(title: threshMenuTitle, action: nil, keyEquivalent: "")
        let threshSubmenu = NSMenu(title: threshMenuTitle)

        for opt in thresholdOptions {
            let item = NSMenuItem(title: opt, action: #selector(onSelectThreshold(_:)), keyEquivalent: "")
            item.target = self
            item.state = (opt.uppercased() == config.threshold.uppercased()) ? .on : .off
            threshSubmenu.addItem(item)
        }

        threshSubmenu.addItem(NSMenuItem.separator())
        let customTitle = isRu ? "Свой порог..." : "Custom threshold..."
        let customItem = NSMenuItem(title: customTitle, action: #selector(onCustomThreshold), keyEquivalent: "")
        customItem.target = self
        threshSubmenu.addItem(customItem)

        threshMenuItem.submenu = threshSubmenu
        statusMenu.addItem(threshMenuItem)

        // 4. Check Interval Submenu
        let intervalMenuTitle = isRu ? "Интервал проверки" : "Check Interval"
        let intervalMenuItem = NSMenuItem(title: intervalMenuTitle, action: nil, keyEquivalent: "")
        let intervalSubmenu = NSMenu(title: intervalMenuTitle)

        for sec in intervalOptions {
            let sInt = Int(sec)
            let label = isRu ? "\(sInt) сек" : "\(sInt) seconds"
            let item = NSMenuItem(title: label, action: #selector(onSelectInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = sInt
            item.state = (Int(config.interval) == sInt) ? .on : .off
            intervalSubmenu.addItem(item)
        }

        intervalMenuItem.submenu = intervalSubmenu
        statusMenu.addItem(intervalMenuItem)

        // 5. Notifications Toggle
        let notifTitle = isRu ? "Оповещения" : "Notifications"
        let notifItem = NSMenuItem(title: notifTitle, action: #selector(onToggleNotifications(_:)), keyEquivalent: "")
        notifItem.target = self
        notifItem.state = config.notifications_enabled ? .on : .off
        statusMenu.addItem(notifItem)

        // 6. Sound Toggle
        let soundTitle = isRu ? "Звуковой сигнал" : "Alert Sound"
        let soundItem = NSMenuItem(title: soundTitle, action: #selector(onToggleSound(_:)), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = config.sound ? .on : .off
        statusMenu.addItem(soundItem)

        statusMenu.addItem(NSMenuItem.separator())

        // 7. Language Submenu
        let langMenuItem = NSMenuItem(title: "Язык / Language", action: nil, keyEquivalent: "")
        let langSubmenu = NSMenu(title: "Язык / Language")

        let langChoices: [(title: String, code: String)] = [
            ("Авто (Система) / Auto (System)", "auto"),
            ("English", "en"),
            ("Русский", "ru")
        ]
        for choice in langChoices {
            let item = NSMenuItem(title: choice.title, action: #selector(onSelectLang(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.code
            item.state = (config.lang == choice.code) ? .on : .off
            langSubmenu.addItem(item)
        }
        langMenuItem.submenu = langSubmenu
        statusMenu.addItem(langMenuItem)

        statusMenu.addItem(NSMenuItem.separator())

        // 8. Open Activity Monitor
        let amTitle = isRu ? "Открыть Мониторинг системы" : "Open Activity Monitor"
        let amItem = NSMenuItem(title: amTitle, action: #selector(openActivityMonitor), keyEquivalent: "")
        amItem.target = self
        statusMenu.addItem(amItem)

        // 9. Create Shortcut to Desktop
        let shortcutTitle = isRu ? "Создать ярлык на рабочем столе" : "Create Shortcut to Desktop"
        let shortcutItem = NSMenuItem(title: shortcutTitle, action: #selector(onCreateDesktopShortcut), keyEquivalent: "")
        shortcutItem.target = self
        statusMenu.addItem(shortcutItem)

        // 10. Quit
        let quitTitle = isRu ? "Выход" : "Quit"
        let quitItem = NSMenuItem(title: quitTitle, action: #selector(onQuit), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)
    }

    func updateTopProcessesUI() {
        guard !topProcessItems.isEmpty else { return }

        if !lastUpdatedStr.isEmpty {
            topHeaderItem?.title = isRu
                ? "📊 Топ по памяти (обн. \(lastUpdatedStr)):"
                : "📊 Top Memory (upd. \(lastUpdatedStr)):"
        }

        let threshBytes = parseSize(config.threshold) ?? pow(1024, 3)

        for (idx, item) in topProcessItems.enumerated() {
            if idx < lastTopProcs.count {
                let proc = lastTopProcs[idx]
                let memStr = formatBytes(proc.rssBytes)
                let icon = (proc.rssBytes >= threshBytes) ? "🔴" : "🔹"
                let shortName = String(proc.name.prefix(28))
                item.title = "  \(icon) \(idx + 1). \(shortName): \(memStr) (PID \(proc.pid))"
            } else {
                item.title = "  #\(idx + 1): —"
            }
        }
    }

    // MARK: - Menu Actions

    @objc func onManualRefresh() {
        checkMemory()
    }

    @objc func onSelectThreshold(_ sender: NSMenuItem) {
        config.threshold = sender.title
        saveConfig()
        rebuildMenu()
        checkMemory()
    }

    @objc func onCustomThreshold() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = isRu ? "Настройка порога" : "Custom Threshold"
        alert.informativeText = isRu
            ? "Введите лимит памяти (например: 750MB, 1.2GB, 2500M):"
            : "Enter memory limit (e.g. 750MB, 1.2GB, 2500M):"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: isRu ? "Отмена" : "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.stringValue = config.threshold
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if parseSize(text) != nil {
                config.threshold = text
                saveConfig()
                rebuildMenu()
                checkMemory()
            } else {
                let errAlert = NSAlert()
                errAlert.alertStyle = .warning
                errAlert.messageText = isRu ? "Ошибка формата" : "Invalid Format"
                errAlert.informativeText = isRu
                    ? "Неверный формат. Примеры: 500MB, 1GB, 1.5G"
                    : "Invalid format. Examples: 500MB, 1GB, 1.5G"
                errAlert.runModal()
            }
        }
    }

    @objc func onSelectInterval(_ sender: NSMenuItem) {
        let sec = Double(sender.tag)
        config.interval = sec
        saveConfig()
        rebuildMenu()
        checkMemory()
        startTimer(interval: sec)
    }

    @objc func onToggleNotifications(_ sender: NSMenuItem) {
        config.notifications_enabled.toggle()
        saveConfig()
        sender.state = config.notifications_enabled ? .on : .off
    }

    @objc func onToggleSound(_ sender: NSMenuItem) {
        config.sound.toggle()
        saveConfig()
        sender.state = config.sound ? .on : .off
    }

    @objc func onSelectLang(_ sender: NSMenuItem) {
        if let code = sender.representedObject as? String {
            config.lang = code
            resolveLanguage()
            saveConfig()
            rebuildMenu()
            checkMemory()
        }
    }

    @objc func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.open(url)
    }

    @objc func onCreateDesktopShortcut() {
        let sourceURL = Bundle.main.bundleURL.pathExtension == "app"
            ? Bundle.main.bundleURL
            : URL(fileURLWithPath: CommandLine.arguments[0])

        guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            return
        }

        let shortcutName = sourceURL.lastPathComponent
        let destURL = desktopURL.appendingPathComponent(shortcutName)

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }

            // Create native macOS Finder Alias via bookmark file, fallback to symlink
            do {
                let bookmarkData = try sourceURL.bookmarkData(
                    options: .suitableForBookmarkFile,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                try URL.writeBookmarkData(bookmarkData, to: destURL)
            } catch {
                try FileManager.default.createSymbolicLink(at: destURL, withDestinationURL: sourceURL)
            }

            let title = isRu ? "Ярлык создан" : "Shortcut Created"
            let msg = isRu
                ? "Ярлык '\(shortcutName)' успешно добавлен на рабочий стол."
                : "Shortcut '\(shortcutName)' was created on your Desktop."
            sendNotification(title: title, subtitle: "Desktop", message: msg, sound: false)
        } catch {
            NSApplication.shared.activate(ignoringOtherApps: true)
            let errAlert = NSAlert()
            errAlert.alertStyle = .warning
            errAlert.messageText = isRu ? "Ошибка создания ярлыка" : "Failed to Create Shortcut"
            errAlert.informativeText = error.localizedDescription
            errAlert.runModal()
        }
    }

    @objc func onQuit() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

