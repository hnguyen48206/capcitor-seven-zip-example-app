import CoreBluetooth
import BackgroundTasks
import UIKit
import os.log

struct BLEDevice: Codable {
  let mac: String
  let deviceName: String
  let vehicleID: String
  let status: String
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
  var centralManager: CBCentralManager!
  var targetPeripheral: CBPeripheral?
  let logger: Logger = Logger(subsystem: "com.hnguyen48206.blesrv", category: "background")
  var count = 0;
  private lazy var timer = BackgroundTimer(delegate: nil)
  
  var MacBluetoothsConnectedStr: String?
  var BLEConfigsStr: String?
  var Vehicle_IsMovingStr: String?
  
  var listOfSavedDevice = [BLEDevice]()
  var BLEConfigs = BLEConfig(scan_period:5000, scan_delay:10000)
  var Vehicle_IsMoving =  VehicleIsMoving(Vehicle_IsMoving: true)
  var SCAN_PERIOD: TimeInterval = 5.0
  var SCAN_DELAY: TimeInterval = 10.0
  
  private var detectedDevices: Set<String> = []
  
  private var isScanning = false
  
  override init() {
    super.init()
    centralManager = CBCentralManager(delegate: self, queue: nil)
  }
  
  func reloadLocalStorage()
  {
    detectedDevices.removeAll()
    MacBluetoothsConnectedStr = UserDefaults.standard.string(forKey: "MacBluetoothsConnected") ?? ""
    BLEConfigsStr = UserDefaults.standard.string(forKey: "BLEConfigs") ?? ""
    Vehicle_IsMovingStr = UserDefaults.standard.string(forKey: "Vehicle_IsMoving") ?? ""
    
    do {
      if(MacBluetoothsConnectedStr != "")
      {
        guard let MacBluetoothsConnectedData = MacBluetoothsConnectedStr?.data(using: .utf8) else {
          print("Unable to convert MacBluetoothsConnectedStr to data")
          return
        }
        listOfSavedDevice = try JSONDecoder().decode([BLEDevice].self, from: MacBluetoothsConnectedData)
      }
      
      if(BLEConfigsStr != "")
      {
        guard let BLEConfigsData = BLEConfigsStr?.data(using: .utf8) else {
          print("Unable to convert BLEConfigsStr to data")
          return
        }
        BLEConfigs = try JSONDecoder().decode(BLEConfig.self, from: BLEConfigsData)
      }
      
      if(Vehicle_IsMovingStr != "")
      {
        guard let Vehicle_IsMovingData = Vehicle_IsMovingStr?.data(using: .utf8) else {
          print("Unable to convert Vehicle_IsMovingStr to data")
          return
        }
        Vehicle_IsMoving = try JSONDecoder().decode(VehicleIsMoving.self, from: Vehicle_IsMovingData)
      }
      
    } catch {
      print("Failed to decode JSON: \(error.localizedDescription)")
    }
    
    SCAN_PERIOD = TimeInterval(round(Double(BLEConfigs.scan_period)/1000))
    SCAN_DELAY = TimeInterval(round(Double(BLEConfigs.scan_delay)/1000))
  }
  
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state == .poweredOn {
      startScanningInForeground()
      print("[DEBUG] - Start Scanning From Load")
      os_log("[DEBUG] - Start Scanning From Load", log: OSLog.default, type: .debug)
    }
  }
  
  func startScanning() {
    reloadLocalStorage()
    isScanning = true;
    if(Vehicle_IsMoving.Vehicle_IsMoving)
    {
      centralManager.scanForPeripherals(withServices: nil, options: nil)
    }
  }
  
  func startScanningInForeground() {
    reloadLocalStorage()
    isScanning = true;
    if(Vehicle_IsMoving.Vehicle_IsMoving)
    {
      centralManager.scanForPeripherals(withServices: nil, options: nil)
      let taskID = timer.executeAfterDelay(delay: SCAN_PERIOD) {
        self.stopScanningInForeground()
      }
    }
    
  }
  
  func stopScanning() {
    isScanning = false
    centralManager.stopScan()
    updateDeviceStatus()
    print("Stop Scanning")
    os_log("[DEBUG] - Stop Scanning", log: OSLog.default, type: .debug)
  }
  
  func stopScanningInForeground() {
    isScanning = false
    centralManager.stopScan()
    updateDeviceStatus()
    print("Stop Scanning")
    os_log("[DEBUG] - Stop Scanning in Foreground", log: OSLog.default, type: .debug)
    let taskID = timer.executeAfterDelay(delay: SCAN_DELAY) {
      self.startScanningInForeground()
    }
  }
  
  
  func updateDeviceStatus()
  {
    var newListOfSavedDevice = [BLEDevice]()
    listOfSavedDevice.forEach { device in
      if(detectedDevices.contains(device.mac))
      {
        let newDevice = BLEDevice(mac:device.mac, deviceName: device.deviceName, vehicleID: device.vehicleID, status: "on")
        newListOfSavedDevice.append(newDevice)
      }
      else
      {
        let newDevice = BLEDevice(mac:device.mac, deviceName: device.deviceName, vehicleID: device.vehicleID, status: "off")
        newListOfSavedDevice.append(newDevice)
      }
    }
    do {
      let jsonData = try JSONEncoder().encode(newListOfSavedDevice)
      let jsonString = String(data: jsonData, encoding: .utf8)
      UserDefaults.standard.set(jsonString, forKey: "MacBluetoothsConnected")
    } catch {
      print("Failed to encode devices: \(error.localizedDescription)")
    }
  }
  
  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    // Handle discovered peripheral
    //    self.count+=1
    print("\(count) - Discovered \(peripheral.name ?? "unknown device") \(peripheral.identifier.uuidString)")
    logger.log("[DEBUG] - \(self.count) - Discovered \(peripheral.name ?? "unknown device") \(peripheral.identifier.uuidString)")
    
    detectedDevices.insert(peripheral.identifier.uuidString)
  }
  
  
  func scheduleBLEScan() {
    let request = BGAppRefreshTaskRequest(identifier: "com.hnguyen48206.blesrv")
    request.earliestBeginDate = Date(timeIntervalSinceNow: SCAN_DELAY)
    do {
      try BGTaskScheduler.shared.submit(request)
      logger.log("[DEBUG] - Registered next schedule.")
    } catch {
      print("Could not schedule BLE scan: \(error)")
      logger.log("[DEBUG] - Could not schedule BLE scan: \(error)")
    }
  }
  
}
