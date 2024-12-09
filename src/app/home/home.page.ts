import { Component } from '@angular/core';
import { Preferences } from '@capacitor/preferences';

@Component({
  selector: 'app-home',
  templateUrl: 'home.page.html',
  styleUrls: ['home.page.scss'],
})
export class HomePage {
  addDeviceID = '';
  rmDeviceID = '';
  currentList: string | null = '';
  arr: any[] = [];
  updateInterval: any;
  pastScanLogs: any[] = [];
  ionViewWillEnter() {
    this.getCurrentList();
  }

  async startBLESER() {
    // await BLEServ.startService();
    this.updateInterval = setInterval(() => {
      this.getCurrentList();
    }, 2000);
  }
  async stopBLESER() {
    // await BLEServ.stopService();
    if (this.updateInterval != null) clearInterval(this.updateInterval);
  }
  async getCurrentList() {
    let res = await Preferences.get({ key: 'MacBluetoothsConnected' });
    this.currentList = res.value;
    this.arr = JSON.parse(this.currentList ? this.currentList : '[]');
    console.log(this.currentList);
  }
  async setNewDevice() {
    if (this.isValidMACAddress(this.addDeviceID)) {
      //add
      this.arr.push({
        mac:
          this.addDeviceID == ''
            ? 'AD54DCDC-3077-A0DE-70EC-888DE895C7EC'
            : this.addDeviceID,
        vehicleID: 'ABC',
        status: 'on',
        deviceName: 'test',
        isAutoConnect: true,
      });
      await Preferences.set({
        key: 'MacBluetoothsConnected',
        value: JSON.stringify(this.arr),
      });
      alert('Add OK');
      this.addDeviceID = '';
      this.getCurrentList();
    }
  }
  async rmDevice() {
    if (this.isValidMACAddress(this.rmDeviceID)) {
      //rm
      this.arr = this.arr.filter((device) => device.mac != this.rmDeviceID);
      await Preferences.set({
        key: 'MacBluetoothsConnected',
        value: JSON.stringify(this.arr),
      });
      alert('Rm OK');
      this.rmDeviceID = '';
      this.getCurrentList();
    }
  }
  isValidMACAddress(mac: string) {
    const macRegex = /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/;
    // return macRegex.test(mac);
    return true;
  }

  async getScanHistory()
  {
    let res = await Preferences.get({ key: 'scanHistoryLog' });
    if(res)
      this.pastScanLogs = (res.value as String).split("devider");
  }
}
