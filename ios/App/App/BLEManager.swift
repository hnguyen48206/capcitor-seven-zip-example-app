import CoreBluetooth
import BackgroundTasks
import UIKit
import os.log
import UserNotifications
import CoreLocation

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
  let isTesting: Bool
  let connect_delay: Int
}

struct VehicleIsMoving: Codable {
  let Vehicle_IsMoving: Bool
}
enum BluetoothCommand: String, CaseIterable {
  case numQueue = "NUM_QUEUE\r"
  case readAll = "READ_ALL\r"
}

@available(iOS 14.0, *)
class BLEManager: NSObject, CBCentralManagerDelegate, CLLocationManagerDelegate{
  private let locationManager = CLLocationManager()
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
  var BLEConfigs = BLEConfig(scan_period:10000, scan_delay:50000, isTesting: true, connect_delay:900000)
  var Vehicle_IsMoving =  VehicleIsMoving(Vehicle_IsMoving: true)
  var SCAN_PERIOD: TimeInterval = 10.0
  var SCAN_DELAY: TimeInterval = 50.0
  var CONNECT_DELAY: TimeInterval = 900
  var targetDevice: CBPeripheral?
  var isFG = true
  let listOfBLEServ: [CBUUID] = [CBUUID(string: "0x180D"), CBUUID(string: "0x5533")] //HeartRate
  var listOfLatestSans = [String]()
  let df = DateFormatter()
  
  private var detectedDevices: Set<String> = []
  
  private var isScanning = false
  
  override init() {
    super.init()
    centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    requestLocalNotification()
    setupLocationManager()
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    scanHistoryLog(isGet: true)
  }
  
  func setupLocationManager()
  {
    // Setup Location Manager
    locationManager.delegate = self
    locationManager.requestAlwaysAuthorization()
    locationManager.allowsBackgroundLocationUpdates = true
    locationManager.pausesLocationUpdatesAutomatically = false
    locationManager.showsBackgroundLocationIndicator = false
    locationManager.startUpdatingLocation()
    locationManager.startMonitoringSignificantLocationChanges()
  }
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation])
  { guard let location = locations.last
    else { return }
    printLog(msg: "Updated Location: \(location)")
  }
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    printLog(msg: "Failed to get location: \(error)")
  }
  
  func scanHistoryLog(isGet:Bool)
  {
    timer.executeAfterDelay(delay: 0.5) {
      if(isGet)
      {
        var stringArray = UserDefaults.standard.string(forKey: "CapacitorStorage.scanHistoryLog") ?? ""
        if(!stringArray.isEmpty)
        {
          self.listOfLatestSans = stringArray.components(separatedBy: "devider")
        }
      }
      else
      {
        if(!self.listOfLatestSans.isEmpty)
        {
          let singleString = self.listOfLatestSans.joined(separator: "devider")
          UserDefaults.standard.set(singleString, forKey: "CapacitorStorage.scanHistoryLog")
        }
      }
    }
    
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
    printLog(msg: "MacBluetoothsConnectedStr \(String(describing: MacBluetoothsConnectedStr))")
    do {
      if(MacBluetoothsConnectedStr != "")
      {
        guard let MacBluetoothsConnectedData = MacBluetoothsConnectedStr?.data(using: .utf8) else {
          printLog(msg: "Unable to convert MacBluetoothsConnectedStr to data")
          return
        }
        //print("MacBluetoothsConnectedData \(MacBluetoothsConnectedData)")
        listOfSavedDevice = try JSONDecoder().decode([BLEDevice].self, from: MacBluetoothsConnectedData)
        printLog(msg: "listOfSavedDevice \(listOfSavedDevice.description)")
      }
      
      if(BLEConfigsStr != "")
      {
        guard let BLEConfigsData = BLEConfigsStr?.data(using: .utf8) else {
          printLog(msg: "[DEBUG] - Unable to convert BLEConfigsStr to data")
          return
        }
        BLEConfigs = try JSONDecoder().decode(BLEConfig.self, from: BLEConfigsData)
      }
      
      if(Vehicle_IsMovingStr != "")
      {
        guard let Vehicle_IsMovingData = Vehicle_IsMovingStr?.data(using: .utf8) else {
          printLog(msg: "[DEBUG] - Unable to convert Vehicle_IsMovingStr to data")
          return
        }
        Vehicle_IsMoving = try JSONDecoder().decode(VehicleIsMoving.self, from: Vehicle_IsMovingData)
      }
      
    } catch {
      printLog(msg: "[DEBUG] - Failed to decode JSON: \(error.localizedDescription)")
    }
    
    SCAN_PERIOD = TimeInterval(round(Double(BLEConfigs.scan_period)/1000))
    SCAN_DELAY = TimeInterval(round(Double(BLEConfigs.scan_delay)/1000))
  }
  
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    switch central.state {
    case .poweredOn:
      startScanningInForeground()
      printLog(msg: "[DEBUG] - Start Scanning From Load")
      //      os_log("[DEBUG] - Start Scanning From Load", log: OSLog.default, type: .debug)
      blSettingStatus = true
    case .poweredOff, .unauthorized, .unsupported, .unknown, .resetting:
      printLog(msg: "[DEBUG] - Bluetooth is not available.")
      //      os_log("[DEBUG] - Bluetooth is not available.", log: OSLog.default, type: .debug)
      blSettingStatus = false
    @unknown default:
      printLog(msg: "[DEBUG] - A new state is available that is not handled.")
    }
  }
  
  func addScanLogHistory(deviceList: String)
  {
    if(listOfLatestSans.count > 200)
    {
      listOfLatestSans.removeFirst()
    }
    let newItem = df.string(from: Date()) + "_" + deviceList
    //    printLog(msg: newItem)
    listOfLatestSans.append(newItem)
    scanHistoryLog(isGet: false)
  }
  
  func startScanning() {
    if(!isScanning)
    {
      isScanning = true;
      
      let options: [String: Any] = [
        CBCentralManagerScanOptionAllowDuplicatesKey: false,
        CBConnectPeripheralOptionNotifyOnConnectionKey: true
      ]
      
      reloadLocalStorage()
      if(Vehicle_IsMoving.Vehicle_IsMoving && blSettingStatus && !isTargetDeviceConnected())
      {
        getCurrentConnectedList()
        centralManager.scanForPeripherals(withServices: listOfBLEServ, options: options)
      }
    }
    else
    {
      printLog(msg: "[DEBUG] - No Scanning in BG cause the FG scan is happening")
      //      os_log("[DEBUG] - No Scanning in BG cause the FG scan is happening", log: OSLog.default, type: .debug)
    }
  }
  
  func startScanningInForeground() {
    
    DispatchQueue.main.asyncAfter(deadline: .now()) {
      if(self.Vehicle_IsMoving.Vehicle_IsMoving && self.isFG && self.blSettingStatus && !self.isTargetDeviceConnected())
      {
        let options: [String: Any] = [
          CBCentralManagerScanOptionAllowDuplicatesKey: true,
          CBConnectPeripheralOptionNotifyOnConnectionKey: true
        ]
        self.printLog(msg: "[DEBUG] - Start Scanning in FG")
        self.reloadLocalStorage()
        self.isScanning = true;
        self.getCurrentConnectedList()
        self.centralManager.scanForPeripherals(withServices: self.listOfBLEServ, options: options)
      }
      else if(self.Vehicle_IsMoving.Vehicle_IsMoving && !self.isFG && self.blSettingStatus && !self.isTargetDeviceConnected())
      {
        self.printLog(msg: "[DEBUG] - Start Scanning in BG plus")
        let options: [String: Any] = [
          CBCentralManagerScanOptionAllowDuplicatesKey: true,
          CBConnectPeripheralOptionNotifyOnConnectionKey: true,
          CBCentralManagerScanOptionSolicitedServiceUUIDsKey: self.listOfBLEServ
        ]
        self.reloadLocalStorage()
        self.isScanning = true;
        self.getCurrentConnectedList()
        self.centralManager.scanForPeripherals(withServices: self.listOfBLEServ, options: options)
      }
      else
      {
        self.printLog(msg: "[DEBUG] - Not moving \(self.Vehicle_IsMoving.Vehicle_IsMoving)) - No BL \(self.blSettingStatus)")
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
    printLog(msg: "[DEBUG] - Stop Scanning in BG")
    //    os_log("[DEBUG] - Stop Scanning in BG", log: OSLog.default, type: .debug)
  }
  
  public func stopScanningInForeground(autorestart:Bool) {
    if(isScanning)
    {
      isScanning = false
      centralManager.stopScan()
      updateDeviceStatus()
    }
    printLog(msg: "[DEBUG] - Stop Scanning in FG or BG plus \(autorestart)")
    //    os_log("[DEBUG] - Stop Scanning in Foreground", log: OSLog.default, type: .debug)
    if(autorestart)
    {
      timer.executeAfterDelay(delay: SCAN_DELAY) {
        self.startScanningInForeground()
      }
    }
  }
  
  func isTargetDeviceConnected() -> Bool
  {
    if(targetDevice != nil && targetDevice?.state.rawValue == 2)
    {
      //      os_log("[DEBUG] - Target Device is already in connection - No scan needed", log: OSLog.default, type: .debug)
      printLog(msg: "[DEBUG] - Target Device is already in connection - No scan needed")
      addScanLogHistory(deviceList: "Target Device is already in connection. No scan needed")
      return true
    }
    else
    {
      return false
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
        
        if(detectedDevices.contains(device.mac) || (targetDevice?.identifier.uuidString == device.mac && isTargetDeviceConnected()))
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
        addScanLogHistory(deviceList: jsonString!)
        //        timer.executeAfterDelay(delay: self.CONNECT_DELAY) {
        //          self.printLog(msg: "[DEBUG] - DELAY BEFORE CONNECTION \(self.CONNECT_DELAY)")
        //          self.connectDevice()
        //        }
      } catch {
        printLog(msg: "[DEBUG] - Failed to encode devices: \(error.localizedDescription)")
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
    printLog(msg: msg)
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
    if(targetDevice != nil && targetDevice?.state.rawValue != 2)
    {
      centralManager.connect(targetDevice!, options: nil)
    }
    else
    {
      printLog(msg: "[DEBUG] TARGET DEVICE is alreay in connection")
      //      os_log("[DEBUG] TARGET DEVICE is alreay in connection", log: OSLog.default, type: .debug)
    }
  }
  
  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    printLog(msg: "[DEBUG] - Connected to \(peripheral.name ?? "Unknown")")
    peripheral.discoverServices(nil)
  }
  
  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    printLog(msg: "[DEBUG] - Failed to connect to \(peripheral.name ?? "Unknown"): \(error?.localizedDescription ?? "No error information")")
  }
  
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let services = peripheral.services {
      for service in services {
        peripheral.discoverCharacteristics(nil, for: service)
      }
    }
  }
  
  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    if let characteristics = service.characteristics {
      for characteristic in characteristics {
        // Write value to characteristic
        if characteristic.properties.contains(.write) {
          let valueToWrite = "Your command".data(using: .utf8)!
          peripheral.writeValue(valueToWrite, for: characteristic, type: .withResponse)
        }
      }
    }
  }
  func scheduleBLEScan() {
    //    let request = BGAppRefreshTaskRequest(identifier: "com.hnguyen48206.blesrv.ios")
    countPendingTask()
    let request = BGProcessingTaskRequest(identifier: "com.hnguyen48206.blesrv.ios")
    request.requiresNetworkConnectivity = false
    request.requiresExternalPower = false
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60.0)
    do {
      try BGTaskScheduler.shared.submit(request)
      logger.log("[DEBUG] - Registered next schedule.")
    } catch {
      printLog(msg: "[DEBUG] - Could not schedule BLE scan: \(error)")
      logger.log("[DEBUG] - Could not schedule BLE scan: \(error)")
    }
  }
  
  func requestLocalNotification() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if granted {
        self.printLog(msg: "[DEBUG] - Permission granted")
      } else if let error = error {
        self.printLog(msg: "[DEBUG] - Permission denied: \(error.localizedDescription)")
      }
    }
  }
  
  func pushLocalNoti(msg: String)
  {
    if(BLEConfigs.isTesting)
    {
      let content = UNMutableNotificationContent()
      content.title = "BLE Scanning"
      content.body = msg
      content.sound = nil
      content.categoryIdentifier = "silentCategory"
      
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
      let id = "hnguyen48206"
      let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
      let center = UNUserNotificationCenter.current()
      center.removeDeliveredNotifications(withIdentifiers: [id])
      center.removePendingNotificationRequests(withIdentifiers: [id])
      
      center.add(request) { error in
        if let error = error {
          self.printLog(msg: "[DEBUG] - Error adding notification: \(error.localizedDescription)")
        }
      }
    }
    else
    {
      printLog(msg: "[DEBUG] - No testing mode")
    }
  }
  
  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    if let error = error { printLog(msg: "Disconnected from peripheral \(peripheral.name ?? "Unknown") with error: \(error.localizedDescription)") }
    else { printLog(msg: "Disconnected from peripheral \(peripheral.name ?? "Unknown") successfully") }
  }
  
  func countPendingTask()
  {
    BGTaskScheduler.shared.getPendingTaskRequests { (taskRequests) in
      let pendingTaskCount = taskRequests.count
      self.printLog(msg: "Number of pending task requests: \(pendingTaskCount)") }
  }
  
  //  func writeValue() {
  //
  //    if (isTargetDeviceConnected()) { //check if myPeripheral is connected to send data
  //          BluetoothCommand.allCases.forEach {
  //              let dataToSend: Data = $0.rawValue.data(using: .utf8)!
  //            targetDevice?.writeValue(dataToSend, for: myCharacteristic, type: .withResponse)
  //          }
  //
  //      } else {
  //          print("Not connected")
  //      }
  //
  //  }
  
  public func printLog(msg:String)
  {
    if(BLEConfigs.isTesting)
    {
      print(msg)
    }
  }
  func getCurrentConnectedList()
  {
    let peripherals = centralManager.retrieveConnectedPeripherals(withServices: listOfBLEServ)
    for peripheral in peripherals {
      let msg = "[DEBUG] - \(self.count) - Discovered CONNECTED \(peripheral.name ?? "unknown device") \(peripheral.identifier.uuidString) \(peripheral.state)"
      printLog(msg: msg)
      detectedDevices.insert(peripheral.identifier.uuidString)
      checkIfTargetDeviceToConnect(peripheral: peripheral)
    }
  }
}
