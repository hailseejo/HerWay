import Flutter
import MessageUI
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
    let channel = FlutterMethodChannel(
      name: "herway/sms",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "composeSms",
            let arguments = call.arguments as? [String: Any],
            let recipient = arguments["recipient"] as? String,
            let body = arguments["body"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard MFMessageComposeViewController.canSendText() else {
        result(FlutterError(
          code: "sms_unavailable",
          message: "SMS is unavailable on this device",
          details: nil
        ))
        return
      }

      DispatchQueue.main.async {
        let composer = MFMessageComposeViewController()
        composer.recipients = [recipient]
        composer.body = body
        composer.messageComposeDelegate = self
        self.topViewController()?.present(composer, animated: true)
        result(true)
      }
    }
  }

  private func topViewController(
    _ controller: UIViewController? = nil
  ) -> UIViewController? {
    let root = controller ?? UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
      .first
    if let presented = root?.presentedViewController {
      return topViewController(presented)
    }
    if let navigation = root as? UINavigationController {
      return topViewController(navigation.visibleViewController)
    }
    if let tab = root as? UITabBarController {
      return topViewController(tab.selectedViewController)
    }
    return root
  }
}

extension AppDelegate: MFMessageComposeViewControllerDelegate {
  func messageComposeViewController(
    _ controller: MFMessageComposeViewController,
    didFinishWith result: MessageComposeResult
  ) {
    controller.dismiss(animated: true)
  }
}
