module.exports = {
  title: "pimatic-tado-reloaded device config schemas"
  TadoThermostat: {
    title: "TadoThermostat config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:
      zone:
        description: "Zone id"
        type: "integer"
        default: 1
      interval:
        description: "Interval in ms to interace with Tado web, the minimal reading interval should be 120000 (2 min)"
        type: "integer"
        default: 120000
      heating:
        description: "Supports heating if enabled"
        type: "boolean"
        default: true
      cooling:
        description: "Supports cooling if enabled"
        type: "boolean"
        default: false
      heatcool:
        description: "Supports heating and cooling if enabled"
        type: "boolean"
        default: false
      minThresholdCelsius:
        description: "supported minimum temperature range for this device (in degrees Celsius)"
        type: "number"
        default: 5
      maxThresholdCelsius:
        description: "supported maximum temperature range for this device (in degrees Celsius)"
        type: "number"
        default: 30
    }
  TadoPresence: {
    title: "TadoPresence config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:
      deviceId:
        description: "Tado id of the mobile device"
        type: "integer"
        default: 1
      interval:
        description: "Interval in ms to interace with Tado web, the minimal reading interval should be 120000 (2 min)"
        type: "integer"
        default: 120000
    }
}
