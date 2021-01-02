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
interval:"Interval in ms to interace with Tado web, the minimal reading interval should be 120000 (2 min)"
  default: 120000
heating: "Supports heating if enabled"
  default: true
cooling: "Supports cooling if enabled"
  default: false
heatcool: "Supports heating and cooling if enabled"
  default: false
minThresholdCelsius: "supported minimum temperature range for this device (in degrees Celsius)"
  default: 5
maxThresholdCelsius: "supported maximum temperature range for this device (in degrees Celsius)"
  default: 30
```

### The rules syntax
```
thermostat <TadoThermostat device>
    heat | heatcool | cool |
    on | eco | off |
    setpoint [<temperature>|<$temp variable>] |
    setpoint low [<temperature>|<$temp variable>] | setpoint high [<temperature>|<$temp variable] |
    program manual | program auto
```

### The variables to be set
```
- setPoint: The target temperature in heat or cool mode.
- setPointLow: The low target temperature in heatcool mode. Below that value the heater will turn on. The second input in the gui.
- setPointHigh: The high target temperature in heatcool mode. Above that value the cooler with turn on. The third input in the gui
- eco: Set the whole thermostat in eco state
- power: Switch the thermostat on or off
- mode: The current mode of the heater (heat,heatcool or cool)
- program: The current program  (manual or auto)
```

### The state variables
```
- active: True if heater or cooler is on
- heater: True if the heater is on
- cooler: True if the cooler is on
```

With this device you get the maximum thermostat functionality in Google Assistant. This device can be added in pimatic-assistant.
Real heaters and coolers can be connected via rules based on the TadoThermostat variables.
