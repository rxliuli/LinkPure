import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var methodChannel: FlutterMethodChannel?
  
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    // 设置 Method Channel 用于接收主题变化
    methodChannel = FlutterMethodChannel(
      name: "com.rxliuli.linkpure/theme",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    
    methodChannel?.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "setThemeMode" {
        if let args = call.arguments as? [String: Any],
           let mode = args["mode"] as? String {
          self?.updateWindowAppearance(mode: mode)
          result(nil)
        } else {
          result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
  
  private func updateWindowAppearance(mode: String) {
    DispatchQueue.main.async {
      switch mode {
      case "dark":
        self.appearance = NSAppearance(named: .darkAqua)
      case "light":
        self.appearance = NSAppearance(named: .aqua)
      default:
        // system - 跟随系统
        self.appearance = nil
      }
    }
  }
}
