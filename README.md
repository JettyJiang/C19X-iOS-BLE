# C19X-iOS-BLE
An investigation into options for resuming beacon tracking for iOS devices in background mode after going out of range for long periods.

Abbreviations for app state
- F = Foreground
- B = Background
- S = Suspended
- T = Terminated

The current C19X-iOS app is able to detect and track Android devices in F/B and iOS devices in F/B/S/T. For iOS devices in B/S/T it has several limitations once two iOS devices (A and B) have discovered each other and established connection.
- Airplane mode ON -> Wait over 1 minute -> OFF on Phone A in B/S/T will terminate connection and Phone B in B/S/T won't be able to detect and track A again until the app on either A or B enters F again. This is caused by Phone A UUID change, thus the pending connect from B based on an expired UUID will not be established. Furthermore, didDiscover is not called in B as the A is still the same known device, thus B has no means of reconnecting.
- Phone A in B/S/T going out of range of Phone B in B/S/T for over 20 minutes will terminuate connection and Phone B in B/S/T won't be able to detect and track A again until the app on either A or B enters F again. Like the airplane mode cycle, this is caused by Phone A UUID change after a period of bluetooth inactivity, thus the pending connect from B based on an expired UUID will not be established. Furthermore, didDiscover is not called in B as the A is still the same known device, thus B has no means of reconnecting.

Experiments have been conducted to understand and address this issue, ideals that have been tested but failed or not fully resolved the problem include:
1. Use pending "write withResponse" request from CBCentralManager to extract new UUID from CBPeripheralManager (didWrite). This works for short periods, implying CoreBluetooth is able to transfer the pending request from one UUID to the next but it does not notify CBCentralManager.
2. Use pending "setNotifyValue" request from CBCentralManager to extract new UUID from CBCentralManager (didUpdateNotificationStateFor). This works for short periods, once again implying CoreBluetooth is capable of transferring the pending request but it only lasts about 1 minute and rarely longer.
3. Use "rotating service UUID" (one-in-many) in advert by CBPeripheralManager and "rotating scan for UUIDs" (all-but-one) in CBCentralManager scan in the hope of triggering "didDiscover" as both peripheral advert and scan parameters have changed, but this did not work. It appears the data is cached and didDiscover is only called once in B/S/T for each physical device.
4. Use "disposible instances" of CBCentralManager to conduct each scan in the hope that didDiscover is called again for the same peripheral when a new CBCentralManager is created to conduct a new scan, but this did not work. It appears that peripheral discovery is reported once for each app instance, rather than each CBCentralManager instance. Doesn't make logical sense as a design.
5. Use BGAppRefresh, BGProcessing and CoreLocation as triggers for CBCentralManager scan call in B/S/T, but this did not work. Scan only triggers didDiscover once for each peripheral, repeated calls make no difference.
