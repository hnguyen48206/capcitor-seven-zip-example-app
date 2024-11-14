import { Component } from '@angular/core';
import { BLEServ } from 'ble-srv';
@Component({
  selector: 'app-home',
  templateUrl: 'home.page.html',
  styleUrls: ['home.page.scss'],
})
export class HomePage  {
  
  async startBLESER() {
    await BLEServ.startService();
  }
  async stopBLESER() {
    await BLEServ.stopService();
  }
}
