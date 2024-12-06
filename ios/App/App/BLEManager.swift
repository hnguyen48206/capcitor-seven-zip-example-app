import CoreBluetooth
import BackgroundTasks
import UIKit
import os.log
import UserNotifications

struct BLEDevice: Codable {
  let mac: String
  let deviceName: String
  let vehicleID: String
  let status: String
  let isAutoConnect: Bool
}

struct BLEConfig: Codable {
  let scan_period: Int
  let scan_delay: Int
}

struct VehicleIsMoving: Codable {
  let Vehicle_IsMoving: Bool
}


@available(iOS 14.0, *)
class BLEManager: NSObject, CBCentralManagerDelegate {
  var blSettingStatus: Bool = true
  var centralManager: CBCentralManager!
  var targetPeripheral: CBPeripheral?
  let logger: Logger = Logger(subsystem: "com.hnguyen48206.blesrv.ios", category: "background")
  var count = 0;
  private lazy var timer = BackgroundTimer(delegate: nil)
  
  var MacBluetoothsConnectedStr: String?
  var BLEConfigsStr: String?
  var Vehicle_IsMovingStr: String?
  
  var listOfSavedDevice = [BLEDevice]()
  var BLEConfigs = BLEConfig(scan_period:10000, scan_delay:10000)
  var Vehicle_IsMoving =  VehicleIsMoving(Vehicle_IsMoving: true)
  var SCAN_PERIOD: TimeInterval = 10.0
  var SCAN_DELAY: TimeInterval = 10.0
  var targetDevice: CBPeripheral?
  var isFG = true
  let listOfBLEServ: [CBUUID] = [CBUUID(string: "0x180D"), CBUUID(string: "0x5533")] //HeartRate
  private var detectedDevices: Set<String> = []
  
  private var isScanning = false
  
  override init() {
    super.init()
    centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    requestLocalNotification()
  }
  
  func reloadLocalStorage(clearDetectedDevices:Bool = true)
  {
    if(clearDetectedDevices)
    {
      detectedDevices.removeAll()
    }
    MacBluetoothsConnectedStr = UserDefaults.standard.string(forKey: "CapacitorStorage.MacBluetoothsConnected") ?? ""
    BLEConfigsStr = UserDefaults.standard.string(forKey: "CapacitorStorage.BLEConfigs") ?? ""
    Vehicle_IsMovingStr = UserDefaults.standard.string(forKey: "CapacitorStorage.Vehicle_IsMoving") ?? ""
    print("MacBluetoothsConnectedStr \(String(describing: MacBluetoothsConnectedStr))")
    do {
      if(MacBluetoothsConnectedStr != "")
      {
        guard let MacBluetoothsConnectedData = MacBluetoothsConnectedStr?.data(using: .utf8) else {
          print("Unable to convert MacBluetoothsConnectedStr to data")
          return
        }
        //        print("MacBluetoothsConnectedData \(MacBluetoothsConnectedData)")
        listOfSavedDevice = try JSONDecoder().decode([BLEDevice].self, from: MacBluetoothsConnectedData)
        print("listOfSavedDevice \(listOfSavedDevice.description)")
      }
      
      if(BLEConfigsStr != "")
      {
        guard let BLEConfigsData = BLEConfigsStr?.data(using: .utf8) else {
          print("[DEBUG] - Unable to convert BLEConfigsStr to data")
          return
        }
        BLEConfigs = try JSONDecoder().decode(BLEConfig.self, from: BLEConfigsData)
      }
      
      if(Vehicle_IsMovingStr != "")
      {
        guard let Vehicle_IsMovingData = Vehicle_IsMovingStr?.data(using: .utf8) else {
          print("[DEBUG] - Unable to convert Vehicle_IsMovingStr to data")
          return
        }
        Vehicle_IsMoving = try JSONDecoder().decode(VehicleIsMoving.self, from: Vehicle_IsMovingData)
      }
      
    } catch {
      print("[DEBUG] - Failed to decode JSON: \(error.localizedDescription)")
    }
    
    SCAN_PERIOD = TimeInterval(round(Double(BLEConfigs.scan_period)/1000))
    SCAN_DELAY = TimeInterval(round(Double(BLEConfigs.scan_delay)/1000))
  }
  
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn:
      startScanningInForeground()
      print("[DEBUG] - Start Scanning From Load")
      os_log("[DEBUG] - Start Scanning From Load", log: OSLog.default, type: .debug)
      blSettingStatus = true
    case .poweredOff, .unauthorized, .unsupported, .unknown, .resetting:
      print("[DEBUG] - Bluetooth is not available.")
      os_log("[DEBUG] - Bluetooth is not available.", log: OSLog.default, type: .debug)
      blSettingStatus = false
    @unknown default:
      print("[DEBUG] - A new state is available that is not handled.")
    }
  }
  
  func startScanning() {
    let options: [String: Any] = [
      CBCentralManagerScanOptionAllowDuplicatesKey: false,
      CBConnectPeripheralOptionNotifyOnConnectionKey: true
    ]
    
    reloadLocalStorage()
    isScanning = true;
    if(Vehicle_IsMoving.Vehicle_IsMoving && blSettingStatus)
    {
      centralManager.scanForPeripherals(withServices: listOfBLEServ, options: options)
      os_log("[DEBUG] - Start Scanning in BG", log: OSLog.default, type: .debug)
    }
  }
  
  func startScanningInForeground() {
    
    DispatchQueue.main.asyncAfter(deadline: .now()) {
      if(self.Vehicle_IsMoving.Vehicle_IsMoving && self.isFG && self.blSettingStatus)
      {
        let options: [String: Any] = [
          CBCentralManagerScanOptionAllowDuplicatesKey: true,
          CBConnectPeripheralOptionNotifyOnConnectionKey: true
        ]
        print("[DEBUG] - Start Scanning in FG")
        self.reloadLocalStorage()
        self.isScanning = true;
        self.centralManager.scanForPeripherals(withServices: self.listOfBLEServ, options: options)
      }
      else if(self.Vehicle_IsMoving.Vehicle_IsMoving && !self.isFG && self.blSettingStatus)
      {
        print("[DEBUG] - Start Scanning in BG plus")
        let options: [String: Any] = [
          CBCentralManagerScanOptionAllowDuplicatesKey: true,
          CBConnectPeripheralOptionNotifyOnConnectionKey: true,
          CBCentralManagerScanOptionSolicitedServiceUUIDsKey: self.listOfBLEServ
        ]
        self.reloadLocalStorage()
        self.isScanning = true;
        self.centralManager.scanForPeripherals(withServices: self.listOfBLEServ, options: options)
      }
      else
      {
        print("[DEBUG] - Not moving \(self.Vehicle_IsMoving.Vehicle_IsMoving)) - No BL \(self.blSettingStatus)")
      }
      self.timer.executeAfterDelay(delay: self.SCAN_PERIOD) {
        self.stopScanningInForeground(autorestart: true)
      }
    }
  }
  
  func stopScanning() {
    isScanning = false
    centralManager.stopScan()
    updateDeviceStatus()
    //    print("Stop Scanning")
    os_log("[DEBUG] - Stop Scanning in BG", log: OSLog.default, type: .debug)
  }
  
  public func stopScanningInForeground(autorestart:Bool) {
    if(isScanning)
    {
      isScanning = false
      centralManager.stopScan()
      updateDeviceStatus()
    }
    print("[DEBUG] - Stop Scanning in FG or BG plus \(autorestart)")
    //    os_log("[DEBUG] - Stop Scanning in Foreground", log: OSLog.default, type: .debug)
    if(autorestart)
    {
      timer.executeAfterDelay(delay: SCAN_DELAY) {
        self.startScanningInForeground()
      }
    }
  }
  
  func updateDeviceStatus()
  {
    
    //        for device in detectedDevices {
    //          print("DETECTED MAC: \(device)")
    //        }
    reloadLocalStorage(clearDetectedDevices: false)
    
    if(!listOfSavedDevice.isEmpty)
    {
      var newListOfSavedDevice = [BLEDevice]()
      listOfSavedDevice.forEach { device in
        //        print("SAVED MAC: \(device.mac)")
        
        if(detectedDevices.contains(device.mac) || (targetDevice?.state.rawValue == 2 && targetDevice?.identifier.uuidString == device.mac))
        {
          //          print("ON")
          let newDevice = BLEDevice(mac:device.mac, deviceName: device.deviceName, vehicleID: device.vehicleID, status: "on", isAutoConnect: device.isAutoConnect)
          newListOfSavedDevice.append(newDevice)
        }
        else
        {
          //          print("OFF")
          let newDevice = BLEDevice(mac:device.mac, deviceName: device.deviceName, vehicleID: device.vehicleID, status: "off", isAutoConnect: device.isAutoConnect)
          newListOfSavedDevice.append(newDevice)
        }
      }
      do {
        let jsonData = try JSONEncoder().encode(newListOfSavedDevice)
        let jsonString = String(data: jsonData, encoding: .utf8)
        UserDefaults.standard.set(jsonString, forKey: "CapacitorStorage.MacBluetoothsConnected")
        pushLocalNoti(msg: jsonString!)
        connectDevice()
      } catch {
        print("[DEBUG] - Failed to encode devices: \(error.localizedDescription)")
      }
    }
    else
    {
      pushLocalNoti(msg: "Done a scan cycle without any device added")
    }
  }
  
  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    // Handle discovered peripheral
    //    self.count+=1
    let msg = "[DEBUG] - \(self.count) - Discovered \(peripheral.name ?? "unknown device") \(peripheral.identifier.uuidString) \(peripheral.state)"
    print(msg)
    os_log("[DEBUG] DEVICE FOUND", log: OSLog.default, type: .debug)
    
    detectedDevices.insert(peripheral.identifier.uuidString)
    checkIfTargetDeviceToConnect(peripheral: peripheral)
  }
  
  
  func checkIfTargetDeviceToConnect(peripheral: CBPeripheral)
  {
    for device in listOfSavedDevice {
      //          print("MAC: \(device.mac)")
      if(device.isAutoConnect && device.mac == peripheral.identifier.uuidString)
      {
        targetDevice = peripheral
        break
      }
    }
  }
  
  func connectDevice()
  {
    if(targetDevice != nil)
    {
      centralManager.connect(targetDevice!, options: nil)
    }
  }
  
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    print("[DEBUG] - Connected to \(peripheral.name ?? "Unknown")")
  }
  
  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    print("[DEBUG] - Failed to connect to \(peripheral.name ?? "Unknown"): \(error?.localizedDescription ?? "No error information")")
  }
  
  
  func scheduleBLEScan() {
    //    let request = BGAppRefreshTaskRequest(identifier: "com.hnguyen48206.blesrv.ios")
    let request = BGProcessingTaskRequest(identifier: "com.hnguyen48206.blesrv.ios")
    request.requiresNetworkConnectivity = false
    request.requiresExternalPower = false
    request.earliestBeginDate = Date(timeIntervalSinceNow: SCAN_DELAY)
    do {
      try BGTaskScheduler.shared.submit(request)
      logger.log("[DEBUG] - Registered next schedule.")
    } catch {
      print("[DEBUG] - Could not schedule BLE scan: \(error)")
      logger.log("[DEBUG] - Could not schedule BLE scan: \(error)")
    }
  }
  
  func requestLocalNotification() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if granted {
        print("[DEBUG] - Permission granted")
      } else if let error = error {
        print("[DEBUG] - Permission denied: \(error.localizedDescription)")
      }
    }
  }
  
  func pushLocalNoti(msg: String)
  {
    let content = UNMutableNotificationContent()
    content.title = "BLE Scanning"
    content.body = msg
    content.sound = UNNotificationSound.default
    
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let id = "hnguyen48206"
    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    let center = UNUserNotificationCenter.current()
    center.removeDeliveredNotifications(withIdentifiers: [id])
    center.removePendingNotificationRequests(withIdentifiers: [id])
    
    center.add(request) { error in
      if let error = error {
        print("[DEBUG] - Error adding notification: \(error.localizedDescription)")
      }
    }
  }
  
  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    if let error = error { print("Disconnected from peripheral \(peripheral.name ?? "Unknown") with error: \(error.localizedDescription)") }
    else { print("Disconnected from peripheral \(peripheral.name ?? "Unknown") successfully") }
  }
}
