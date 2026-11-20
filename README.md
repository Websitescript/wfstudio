# WF Studio — watch face studio + BLE flasher (Flutter)

## Folder structure
lib/
  core/rgb565.dart        photo -> 240x280 RGB565 (crop, encode, decode)
  core/wf_bin.dart        model, CRC16/32, .bin compile / parse / validate
  ble/flasher.dart        permissions, scan, MTU, chunking, ACK/NACK window, packet log
  ui/studio_screen.dart   touch editor with live preview
  (to add) data/gallery.dart (Hive box of saved faces), ui/explore_screen.dart,
           ui/flash_screen.dart, ui/logger_screen.dart (wraps BleFlasher.log + dumpGatt + sendRaw)

## Android manifest
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>

## IMPORTANT
The .bin layout ("WFS1") and BLE framing are placeholders. boAt's real format and GATT
protocol are not public. Capture an official face transfer (Developer options > Bluetooth HCI
snoop log > Wireshark), then update WfBin and FlashProfile/frame bytes to match.
Never flash until validate() passes against the real format; a wrong transfer can brick the watch.
