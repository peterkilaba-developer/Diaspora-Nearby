import Flutter
import UIKit
import GooglePlaces

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let placesApiKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String,
       !placesApiKey.isEmpty,
       !placesApiKey.contains("$(") {
      GMSPlacesClient.provideAPIKey(placesApiKey)
    } else {
      #if DEBUG
      NSLog("[WARNING] GOOGLE_MAPS_API_KEY is not configured in Info.plist / xcconfig.")
      #else
      fatalError("GOOGLE_MAPS_API_KEY must be injected by the selected build configuration")
      #endif
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
