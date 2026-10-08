//
//  UpdateChecker.swift
//  Textream
//
//  Created by Fatih Kadir Akın on 9.02.2026.
//

import AppKit

class UpdateChecker {
    static let shared = UpdateChecker()

    // 繁中改版：check this fork's releases, not the original's — updating to an
    // original release would silently drop the Traditional Chinese fixes.
    private let repoOwner = "wakichuang"
    private let repoName = "textream-zh"

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Check GitHub for the latest release and prompt the user if an update is available.
    func checkForUpdates(silent: Bool = false) {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            DispatchQueue.main.async {
                if let error {
                    if !silent {
                        self.showError("無法檢查更新，請確認網路連線。\n\(error.localizedDescription)")
                    }
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String,
                      let htmlURL = json["html_url"] as? String else {
                    if !silent {
                        self.showError("讀不到發佈資訊，請稍後再試。")
                    }
                    return
                }

                let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

                if self.isVersion(latestVersion, newerThan: self.currentVersion) {
                    self.showUpdateAvailable(latestVersion: latestVersion, releaseURL: htmlURL)
                } else if !silent {
                    self.showUpToDate()
                }
            }
        }.resume()
    }

    // MARK: - Version comparison

    private func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    // MARK: - Alerts

    private func showUpdateAvailable(latestVersion: String, releaseURL: String) {
        let alert = NSAlert()
        alert.messageText = "有新版：Textream 繁中版 \(latestVersion)"
        alert.informativeText = "你目前是 \(currentVersion)。到發佈頁面下載新版的原始碼，在資料夾裡執行 zh/install.sh 就能更新。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "查看更新說明")
        alert.addButton(withTitle: "稍後")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: releaseURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = "已是最新版"
        alert.informativeText = "Textream 繁中版 \(currentVersion) 是目前最新的版本。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "檢查更新失敗"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
