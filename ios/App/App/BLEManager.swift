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
  var BLEConfigs = BLEConfig(scan_period:15000, scan_delay:10000)
  var Vehicle_IsMoving =  VehicleIsMoving(Vehicle_IsMoving: true)
  var SCAN_PERIOD: TimeInterval = 15.0
  var SCAN_DELAY: TimeInterval = 10.0
  var targetDevice: CBPeripheral?
  var isFB = true
  private var detectedDevices: Set<String> = []
  
  private var isScanning = false
  
  override init() {
    super.init()
    centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
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
    print("MacBluetoothsConnectedStr \(MacBluetoothsConnectedStr)")
    do {
      if(MacBluetoothsConnectedStr != "")
      {
        guard let MacBluetoothsConnectedData = MacBluetoothsConnectedStr?.data(using: .utf8) else {
          print("Unable to convert MacBluetoothsConnectedStr to data")
          return
        }
        print("MacBluetoothsConnectedData \(MacBluetoothsConnectedData)")
        listOfSavedDevice = try JSONDecoder().decode([BLEDevice].self, from: MacBluetoothsConnectedData)
        print("listOfSavedDevice \(listOfSavedDevice.description)")
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
    switch central.state {
    case .poweredOn:
      startScanningInForeground()
      print("[DEBUG] - Start Scanning From Load")
      os_log("[DEBUG] - Start Scanning From Load", log: OSLog.default, type: .debug)
    case .poweredOff, .unauthorized, .unsupported, .unknown, .resetting:
      print("Bluetooth is not available.")
    @unknown default:
      print("A new state is available that is not handled.")
    }
  }
  
  func startScanning() {
    let options: [String: Any] = [
    CBCentralManagerScanOptionAllowDuplicatesKey: false,
//    CBCentralManagerScanOptionSolicitedServiceUUIDsKey: [CBUUID(string: "180D")]
    ]
    // let serviceUUIDs: [CBUUID] = [CBUUID(string: "0x181D")] //weight sclae service
    let serviceUUIDs: [CBUUID] = [CBUUID(string: "0x180A"), CBUUID(string: "0x181D")] //carmd m2 device info service

    reloadLocalStorage()
    isScanning = true;
    if(Vehicle_IsMoving.Vehicle_IsMoving)
    {
      centralManager.scanForPeripherals(withServices: serviceUUIDs, options: options)
      os_log("[DEBUG] - Start Scanning in BG", log: OSLog.default, type: .debug)
    }
  }
  
  func startScanningInForeground() {
    
    DispatchQueue.main.asyncAfter(deadline: .now()) {
      //      os_log("[DEBUG] - Start Scanning in Foreground", log: OSLog.default, type: .debug)
      if(self.Vehicle_IsMoving.Vehicle_IsMoving && self.isFB)
      {
        let options: [String: Any] = [
        CBCentralManagerScanOptionAllowDuplicatesKey: false,
    //    CBCentralManagerScanOptionSolicitedServiceUUIDsKey: [CBUUID(string: "180D")]
        ]
        print("[DEBUG] - Start Scanning in FG")
        self.reloadLocalStorage()
        self.isScanning = true;
        self.centralManager.scanForPeripherals(withServices: nil, options: options)
      }
      else if(self.Vehicle_IsMoving.Vehicle_IsMoving && !self.isFB)
      {
        print("[DEBUG] - Start Scanning in BG plus")
        let serviceUUIDs = [CBUUID(string: "0x180A"), CBUUID(string: "0x181D"), CBUUID(string: "0xFFF0")]
        let options: [String: Any] = [
        CBCentralManagerScanOptionAllowDuplicatesKey: false,
        CBCentralManagerScanOptionSolicitedServiceUUIDsKey: serviceUUIDs
        ]
        self.reloadLocalStorage()
        self.isScanning = true;
        self.centralManager.scanForPeripherals(withServices: serviceUUIDs, options: options)
      }
      else
      {
        print("[DEBUG] - Not moving \(self.Vehicle_IsMoving.Vehicle_IsMoving))")
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
    print("Stop Scanning in FG \(autorestart)")
    //    os_log("[DEBUG] - Stop Scanning in Foreground", log: OSLog.default, type: .debug)
    if(autorestart)
    {
      let taskID = timer.executeAfterDelay(delay: SCAN_DELAY) {
        self.startScanningInForeground()
      }
    }
  }
  
  
  func updateDeviceStatus()
  {
    
//    for device in listOfSavedDevice {
//      print("MAC: \(device.mac)")
//    }
    reloadLocalStorage(clearDetectedDevices: false)
    if(!listOfSavedDevice.isEmpty)
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
        UserDefaults.standard.set(jsonString, forKey: "CapacitorStorage.MacBluetoothsConnected")
      } catch {
        print("Failed to encode devices: \(error.localizedDescription)")
      }
    }
  }
  
  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    // Handle discovered peripheral
    //    self.count+=1
    let msg = "[DEBUG] - \(self.count) - Discovered \(peripheral.name ?? "unknown device") \(peripheral.identifier.uuidString) \(peripheral.state)"
    print(msg)
    os_log("[DEBUG] DEVICE FOUND", log: OSLog.default, type: .debug)
    
    detectedDevices.insert(peripheral.identifier.uuidString)
    
//    if(peripheral.identifier.uuidString == "9ABD8859-2F6E-1324-D40A-02D652F5C43C")
//    {
//      targetDevice = peripheral
//      connectDevice()
//    }
  }
  
  func connectDevice()
  {
    if(targetDevice != nil)
    {
      centralManager.connect(targetDevice!, options: nil)
    }
  }
  
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    print("Connected to \(peripheral.name ?? "Unknown")")
  }
  
  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    print("Failed to connect to \(peripheral.name ?? "Unknown"): \(error?.localizedDescription ?? "No error information")")
  }
  
  
  func scheduleBLEScan() {
    //    let request = BGAppRefreshTaskRequest(identifier: "com.hnguyen48206.blesrv")
    let request = BGProcessingTaskRequest(identifier: "com.hnguyen48206.blesrv")
    request.requiresNetworkConnectivity = false
    request.requiresExternalPower = false
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
