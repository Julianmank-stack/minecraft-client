import Foundation
import UserNotifications

/// Native macOS notifications (launch ready, crash alerts, update available).
///
/// UserNotifications only works from a real .app bundle. Running the bare
/// binary (`swift run` / `.build/debug/...`) has no bundle identifier and
/// `UNUserNotificationCenter.current()` throws an unavoidable NSException,
/// so notifications degrade to log lines in that case.
enum Notifier {
    private static var hasAppBundle: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestPermission() {
        guard hasAppBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard hasAppBundle else {
            NSLog("[notification] %@ — %@", title, body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
