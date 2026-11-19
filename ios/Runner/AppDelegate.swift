import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CalendarFiles") {
      CalendarFiles.register(with: registrar)
    }
  }
}

/// "Add to calendar" on iPhone: the API's .ics file, downloaded by the app
/// with the session, shown in the system preview, which offers to add it to
/// the Calendar. The person adds it there; the app writes nothing to the
/// calendar itself and asks for no calendar permission.
final class CalendarFiles: NSObject, FlutterPlugin, UIDocumentInteractionControllerDelegate {
  private var controller: UIDocumentInteractionController?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "rightproperty365/calendar",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(CalendarFiles(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "openIcs",
          let arguments = call.arguments as? [String: Any],
          let bytes = arguments["bytes"] as? FlutterStandardTypedData,
          let name = arguments["name"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    // Only the file name, in the app's own temporary folder.
    let safeName = (name as NSString).lastPathComponent
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      safeName.isEmpty ? "event.ics" : safeName
    )
    do {
      try bytes.data.write(to: url, options: .atomic)
    } catch {
      result(false)
      return
    }
    guard CalendarFiles.topViewController() != nil else {
      result(false)
      return
    }
    let controller = UIDocumentInteractionController(url: url)
    controller.uti = "com.apple.ical.ics"
    controller.delegate = self
    self.controller = controller
    result(controller.presentPreview(animated: true))
  }

  func documentInteractionControllerViewControllerForPreview(
    _ controller: UIDocumentInteractionController
  ) -> UIViewController {
    return CalendarFiles.topViewController() ?? UIViewController()
  }

  func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
    try? FileManager.default.removeItem(at: controller.url ?? URL(fileURLWithPath: "/dev/null"))
    self.controller = nil
  }

  private static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
