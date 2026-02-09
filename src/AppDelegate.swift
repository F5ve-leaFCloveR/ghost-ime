import Cocoa
import InputMethodKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            NSLog("ghost-ime: missing bundle identifier")
            NSApp.terminate(nil)
            return
        }

        let connectionName = (Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String)
            ?? "GhostIME_Connection"

        server = IMKServer(name: connectionName, bundleIdentifier: bundleID)
        if server == nil {
            NSLog("ghost-ime: failed to create IMKServer")
        }
    }
}
