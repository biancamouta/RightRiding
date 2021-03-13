import UIKit
import Flutter
import GoogleMaps
import “GoogleMaps/GoogleMaps.h”

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    GMSServices.provideAPIKey("AIzaSyCIo1CH6g8QVw4AZC0vnOT0JxX6LHDdd0U")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

