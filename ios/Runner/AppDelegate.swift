import Flutter
import UIKit
import ObjectiveC

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override init() {
    super.init()
    AppDelegate.patchFlutterProMotionCrash()
  }

  private static func patchFlutterProMotionCrash() {
    let sel = NSSelectorFromString("createTouchRateCorrectionVSyncClientIfNeeded")
    if let method = class_getInstanceMethod(FlutterViewController.self, sel) {
      let noop: @convention(block) (AnyObject) -> Void = { _ in }
      method_setImplementation(method, imp_implementationWithBlock(noop))
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    AppDelegate.patchFlutterProMotionCrash()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
