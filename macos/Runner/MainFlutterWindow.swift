import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // compact, phone-like window (size set in MainMenu.xib)
    self.isRestorable = false
    DispatchQueue.main.async { // after Flutter's own initial sizing
      self.setContentSize(NSSize(width: 420, height: 760))
      self.center()
    }
    self.minSize = NSSize(width: 380, height: 600)
    self.titlebarAppearsTransparent = true
    self.backgroundColor = NSColor(red: 0.043, green: 0.071, blue: 0.125, alpha: 1)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
