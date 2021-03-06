# pimatic-tado-reloaded
Pimatic plugin for Tado device

This plugin is for connecting Tado devices to Pimatic. Its a reloaded version of the plugin pimatic-tado writen by [TH1485](https://github.com/TH1485/pimatic-tado).

This plugin creates TadoThermostat devices to use in Pimatic, that will give the possibility control Tado thermostats via the gui or via rules.
A TadoThermostat device is a thermostat device for heating control. You can control the target temperature of the thermostat (the setPoint), switch it on of off and sets the mode to manually or shedule (auto). The TadoThermostat also supports an away/home presence function. You need to enable that on your mobile device in the Tado app.

### The plugin

You can install the plugin via the plugins page or add the plugin in config.json.

The Tado Themostats are added via Pimatic's discovery function. Start the 'discover devices' and select the Tado thermostat you want to use. After saving the config, the thermostat can be added to a page in the gui.
In the Tado plugin confug the loginname and the password are required. They are the same as the credentials for the Tado App.
```
loginname: "Tado weblogin name"
password: "Tado webpassword"
debug: "Log information for debugging"
```

TadoThermostat
----

The user interface.

![](/screens/tado-thermostat.png)

### The device config
```
zone: "Tado zone id"
interval: "Interval in ms to interace with Tado web, minimum should be 120000 (2 min)"
  default: 120000
toAutoTime: "Time in seconds to go back to auto, if mode is set to manual. If 0 timer is disabled"
  default: 0
deviceId: "Tado id of the mobile device. Configurable in the Tado mobile app"
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
TemperatureRoom, humidityRoom and connected are visible as value in the gui. Power (on/off), program (manual/auto) and presence (home/away) are visible as buttons in the Gui. All attributes are available as variable.


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
