import Capacitor
import BackgroundTasks
import UIKit
import os.log
@available(iOS 14.0, *)
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
  
  var window: UIWindow?
  var bleManager: BLEManager!
  private lazy var timer = BackgroundTimer(delegate: nil)
  
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    bleManager = BLEManager()
    
    BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.hnguyen48206.blesrv.ios", using: nil) { task in
      //      BGProcessingTask
      //      BGAppRefreshTask
      self.handleBLEScan(task: task as! BGProcessingTask)
    }
    
    return true
  }
  func handleBLEScan(task: BGProcessingTask) {
    bleManager.scheduleBLEScan() // Schedule the next scan
    print("[DEBUG] - Start Scanning in BG")
    os_log("[DEBUG] - Start Scanning in BG", log: OSLog.default, type: .debug)
    bleManager.startScanning()
    
    //In BG, scan only for 10s each
    self.timer.executeAfterDelay(delay: 10) {
      print("[DEBUG] - Should STOP NOW - By Task")
      self.bleManager.logger.log("[DEBUG] - Should STOP NOW")
      self.bleManager.stopScanning()
      task.setTaskCompleted(success: true)
    }
    
    task.expirationHandler = {
      print("[DEBUG] - Should STOP NOW - By Expiration")
      self.bleManager.logger.log("[DEBUG] - Should STOP NOW")
      self.bleManager.stopScanning()
      task.setTaskCompleted(success: false)
    }
  }
  
  
  func applicationWillResignActive(_ application: UIApplication) {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
  }
  
  func applicationDidEnterBackground(_ application: UIApplication) {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    self.bleManager.isFG = false
    self.bleManager.logger.log("[DEBUG] - BG MODE")
    //    self.bleManager.stopScanningInForeground(autorestart: false)
    self.bleManager.scheduleBLEScan() // Schedule the next scan
  }
  
  func applicationWillEnterForeground(_ application: UIApplication) {
    // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    self.bleManager.isFG = true
  }
  
  func applicationDidBecomeActive(_ application: UIApplication) {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
  }
  
  func applicationWillTerminate(_ application: UIApplication) {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
  }
  
  func application(
    _ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    // Called when the app was launched with a url. Feel free to add additional processing here,
    // but if you want the App API to support tracking app url opens, make sure to keep this call
    return ApplicationDelegateProxy.shared.application(app, open: url, options: options)
  }
  
  func application(
    _ application: UIApplication, continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    // Called when the app was launched with an activity, including Universal Links.
    // Feel free to add additional processing here, but if you want the App API to support
    // tracking app url opens, make sure to keep this call
    return ApplicationDelegateProxy.shared.application(
      application, continue: userActivity, restorationHandler: restorationHandler)
  }
  
}

