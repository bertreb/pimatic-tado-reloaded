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
      toAutoTime:
        description: "Time in seconds to go back to auto, after manual is set. If 0, timer is not set"
        type: "number"
        default: 0
      deviceId:
        description: "Tado id of the mobile device"
        type: "integer"
        default: 1
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
