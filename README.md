# pimatic-tado-reloaded
Pimatic plugin for Tado device

This plugin is for connecting Tado devices to Pimatic. Its a reloaded version of the plugin pimatic-tado writen by [TH1485](https://github.com/TH1485/pimatic-tado).

This plugin creates TadoThermostat devices to use within Pimatic. The TadoThermostat can be controlled via the gui or via rules.


TadoThermostat
----
The TadoThermostat device is a thermostat device with a heat, heatcool and cool mode.

![](/screens/tado-thermostat.png)

The default mode is 'heat'. This is the mode for the most common used heating systems. The cool and heatcool modes are for airco type of climate control. In the device config you can enable/disable the modes, depending on your thermostat functionality.

### The device config
```
zone: "Tado zone id"
interval: "Interval in ms to interace with Tado web, minimum should be 120000 (2 min)"
  default: 120000
toAutoTime: "Time in seconds to go back to auto, if mode is set to manual. If 0 timer is disabled"
  default: 0
deviceId: "Tado id of the mobile device"
```

### The available attributes
```
- setPoint: The target temperature. The input in the gui
- temperatureRoom: The thermostat environment temperature
- humidityRoom : The thermostat environment humidity
- power: If thermostat is on or off
- program: The program of the thermostaat; manual or auto
- connected: If the thermostat is connected or not
- presence : If the mobile device is away or at home (deviceId)
```
Only temperatureRoom, humidityRoom and connected, are visible in the gui. All attributes are available as variable.


### The rules syntax
```
thermostat <TadoThermostat device>
    on | off |
    setpoint [<temperature>|<$temp variable>] |
    manual | auto
```

### The variables to be set
```
- setPoint: The target temperature in heat or cool mode. The left input in the gui
- power: Switch the thermostat on or off
- manual : Set the current program to manual
- auto : Set the current program to auto
```

