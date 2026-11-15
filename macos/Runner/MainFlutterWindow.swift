import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    // fixed 360x600, no title bar: the app draws its own title row with
    // traffic lights in the header (style mask also set in MainMenu.xib)
    self.isRestorable = false
    self.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      self.standardWindowButton(b)?.isHidden = true
    }
    DispatchQueue.main.async { // after Flutter's own initial sizing
      self.setContentSize(NSSize(width: 360, height: 600))
      self.center()
    }
    self.backgroundColor = NSColor(red: 0.043, green: 0.071, blue: 0.125, alpha: 1)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
