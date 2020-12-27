module.exports = (env) ->

  # Require the  bluebird promise library
  Promise = env.require 'bluebird'
  # Require the [cassert library](https://github.com/rhoot/cassert).
  assert = env.require 'cassert'
  #require tado client
  M = env.matcher
  _ = require('lodash')
  retry = require 'bluebird-retry'
  commons = require('pimatic-plugin-commons')(env)
  TadoClient = require('./tado-client.coffee')(env)


  class TadoPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>
      
      @base = commons.base @, 'TadoPlugin'
      @client = new TadoClient
      @loginPromise = null # Promise.reject(new Error('tado is not logged in (yet)!'))
      # wait for pimatic to finish starting http(s) server
      @framework.once "server listen", =>
        env.logger.info("Pimatic server started, initializing tado connection") 
        #connecting to tado web interface and acquiring home id  
        @loginPromise =
          retry( () => @client.login(@config.loginname, @config.password),
          {
          throw_original: true
          max_tries: 20
          interval: 50
          backoff: 2
          predicate: (err) ->
            try
              if @config.debug
                env.logger.debug(err.error || (err.code || err))
              return err.error != "invalid_grant"
            catch
              return true
          }
          ).then (connected) =>
            env.logger.info("Login established, connected with tado web interface")
            return @client.me().then (home_info) =>
              env.logger.info("Connected to #{home_info.homes[0].name} with id: #{home_info.homes[0].id}")
              if @config.debug
                env.logger.debug(JSON.stringify(home_info))
              @setHome(home_info.homes[0])
              connected
          .catch (err) ->
            env.logger.error("Could not connect to tado web interface: #{(err.error_description || (err.code || err) )}")
            Promise.reject err
      #
      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("TadoClimate", {
        configDef: deviceConfigDef.TadoClimate,
        createCallback: (config, lastState) =>
          device = new TadoClimate(config, lastState,@framework)
          return device
      })

      @framework.deviceManager.registerDeviceClass("TadoPresence", {
        configDef: deviceConfigDef.TadoPresence,
        createCallback: (config, lastState) =>
          device = new TadoPresence(config, lastState,@framework)
          return device
      })

      @framework.ruleManager.addActionProvider(new TadoActionProvider(@framework))


      @framework.deviceManager.on 'discover', () =>
        #climate devices
        @loginPromise
        .then (success) =>
          @framework.deviceManager.discoverMessage("pimatic-tado-reloaded", "discovering devices...")
          return @client.zones(@home.id)
          .then (zones) =>
            id = null
            for zone in zones
              if zone.type = 'HEATING' and zone.name != 'Hot Water'
                id = @base.generateDeviceId @framework, zone.name.toLowerCase(), id
                id = id.toLowerCase().replace(/\s/g,'')
                config =
                  class: 'TadoClimate'
                  id: id
                  zone: zone.id
                  name: zone.name
                  interval: 120000
                @framework.deviceManager.discoveredDevice(
                  'TadoClimate', config.name, config)
            Promise.resolve(true)
          , (err) ->
            #env.logger.error(err.error_description || err)
            Promise.reject(err)
        .then (success) =>
          return @client.mobileDevices(@home.id)
          .then (mobileDevices) =>
            id = null
            for mobileDevice in mobileDevices
              if mobileDevice.settings.geoTrackingEnabled
                id = @base.generateDeviceId @framework, mobileDevice.name, id
                id = id.toLowerCase().replace(/\s/g,'')
                config =
                  class: 'TadoPresence'
                  id: id
                  deviceId: mobileDevice.id
                  name: mobileDevice.name
                  interval: 120000
                @framework.deviceManager.discoveredDevice(
                  'TadoPresence', config.name, config)
            Promise.resolve(true)
          , (err) ->
            env.logger.error(err.error_description || err)
            Promise.reject(err)
        .catch (err) ->
          #env.logger.error(err.error_description || err)
          Promise.reject(err)

    
    setHome: (home) ->
      if home?
        @home = home

  plugin = new TadoPlugin

  class TadoClimate extends env.devices.TemperatureSensor
    _temperature: null
    _humidity: null

    attributes:
      temperature:
        description: "The measured temperature"
        type: "number"
        unit: '°C'
        acronym: "room temp"
      humidity:
        description: "The actual degree of Humidity"
        type: "number"
        unit: '%'
        acronym: "room hum"
      setPoint:
        description: "The setPoint temperature"
        type: "number"
        unit: '°C'
        acronym: "set temp"
      mode:
        description: "The thermostat mode"
        type: "boolean"
        unit: ''
        acronym: "mode"
        labels: ["AUTO","MANUAL"]
      power:
        description: "The power state"
        type: "boolean"
        unit: ''
        acronym: "power"
        labels: ["ON","OFF"]

    constructor: (@config, lastState,@framework) ->
      @name = @config.name
      @id = @config.id
      @zone = @config.zone
      @_temperature = lastState?.temperature?.value
      @_humidity = lastState?.humidity?.value
      @_setPoint = lastState?.setPoint?.value
      @_mode = lastState?.mode?.value
      @_power = lastState?.power?.value
      @_timestampTemp = null
      @_timestampHum = null
      @lastState = null
      super()
      
      @requestClimate()
      @requestClimateIntervalId =
        setInterval( ( => @requestClimate() ), @config.interval)

    requestClimate: ->
      if plugin.loginPromise? and plugin.home?.id
        plugin.loginPromise
        .then (success) =>
          return plugin.client.state(plugin.home.id, @zone)
        .then (state) =>
          if @config.debug
            env.logger.debug("state received: #{JSON.stringify(state)}")
          if state.sensorDataPoints.insideTemperature.timestamp != @_timestampTemp
            @_temperature = state.sensorDataPoints.insideTemperature.celsius
            @emit "temperature", @_temperature
          if state.sensorDataPoints.humidity.timestamp != @_timestampHum
            @_humidity = state.sensorDataPoints.humidity.percentage
            @emit "humidity", @_humidity
          if state.setting.power?
            if state.setting.power is "ON"
              @_power = true
            else 
              @_power = false
            @emit "power", @_power
          if state.setting.temperature?
            @_setPoint = state.setting.temperature
            @emit "setPoint", @_setPoint
          Promise.resolve(state)
        .catch (err) =>
          env.logger.error(err.error_description || (err.code || err) )
          if @config.debug
            env.logger.debug("homeId=:" + plugin.home.id)
          Promise.reject(err)
           
    setTemperature: (temperature) =>
      return new Promise((resolve,reject) =>
        @_temperature = temperature
        @emit "SetPoint", temperature
        @_mode = "MANUAL"
        @emit "mode", @_mode
        env.logger.debug "Setting temperature setPoint set to #{temperature}"
        plugin.client.setTemperature(plugin.home.id, @zone, temperature)
        .then((res)=>
          resolve()
        ).catch((err)=>
          reject(err)
        )
      )

    setPower: (power) =>
      return new Promise((resolve,reject) =>
        @_power = power
        @emit "power", power
        if power
          _power = "on"
        else
          _power = "off"
        env.logger.debug "Setting power #{power}"
        plugin.client.setPower(plugin.home.id, @zone, _power)
        .then((res)=>
          env.logger.debug "Result plugin.client.setPower: " + JSON.stringify(res,null,2)
          resolve()
        ).catch((err)=>
          reject(err)
        )
      )

    setAuto: () =>
      return new Promise((resolve,reject) =>
        @_mode = "AUTO"
        @emit "mode", @_mode
        env.logger.debug "Setting mode to AUTO"
        plugin.client.setAuto(plugin.home.id, @zone)
        .then((res)=>
          env.logger.debug "Result plugin.client.setAuto: " + JSON.stringify(res,null,2)
          resolve()
        ).catch((err)=>
          reject(err)
        )
      )

    getTemperature: -> Promise.resolve(@_temperature)
    getHumidity: -> Promise.resolve(@_humidity)
    getSetPoint: -> Promise.resolve(@_setPoint)
    getMode: -> Promise.resolve(@_mode)
    getPower: -> Promise.resolve(@_power)

    execute: (command, value) =>
      return new Promise((resolve,reject) =>
        switch command
          when "auto"
            #switch Tado device on with current temp setting
            @setAuto()
            .then(()->
              env.logger.debug "Mode set to AUTO"
              resolve()
            ).catch((err)=>
              env.logger.debug "Failed to setMode to AUTO: " + JSON.stringify(err,null,2)
              reject()
            )
          when "power"
            #switch Tado device on with current temp setting
            @setPower(value)
            .then(()->
              env.logger.debug "Power set to #{_power}"
              resolve()
            ).catch((err)=>
              env.logger.debug "Failed to setPower to #{value}: " + JSON.stringify(err,null,2)
              reject()
            )
          when "temperature"
            if value?
              # check if value(setPoint) is number and is in valid range
              if Number.isNaN(Number value)
                env.logger.debug "setpoint #{value} is not a number"
                reject()
              else
                _setPoint = Number value
                if _setPoint >= 15 and _setPoint <= 25
                  #set overlay to manual mode with new temprature
                  @setTemperature(_setPoint)
                  .then(()=>
                    env.logger.debug "Temperature setPoint set to #{temperature}"
                    resolve()
                  ).catch((err)=>
                    env.logger.debug "Failed setting temperature: " + JSON.stringify(err,null,2)
                    reject()
                  )
                else
                  env.logger.debug "setpoint #{_setPoint} is not within a valid range (15-25)"
                  reject()                  
          else
            env.logger.debug "Unknown command: #{command}"
            reject()
        resolve()
      )

    destroy: () ->
      clearInterval @requestClimateIntervalId if @requestClimateIntervalId?
      super()


  class TadoPresence extends env.devices.PresenceSensor
    _presence: undefined
    _relativeDistance: null

    attributes:
      presence:
        description: "Presence of the human/device"
        type: "boolean"
        labels: ['Home', 'Away']
      relativeDistance:
        description: "Relative distance of human/device from home"
        type: "number"
        unit: '%'

    constructor: (@config, lastState, @framework) ->
      @name = @config.name
      @id = @config.id
      @deviceId = @config.deviceId
      @_presence = lastState?.presence?.value or false
      @_relativeDistance = lastState?.relativeDistance?.value
      @lastState = null
      super()
      
      
      @requestPresence()
      @requestPresenceIntervalId =
        setInterval( ( => @requestPresence() ), @config.interval)

    destroy: () ->
      clearInterval @requestPresenceIntervalId if @requestPresenceIntervalId?
      super()

    requestPresence: ->
      if plugin.loginPromise? and plugin.home?.id
        plugin.loginPromise
        .then (success) =>
          return plugin.client.mobileDevices(plugin.home.id)
        .then (mobileDevices) =>
          if @config.debug
            env.logger.debug("mobileDevices received: #{JSON.stringify(mobileDevices)}")
          for mobileDevice in mobileDevices
            if mobileDevice.id == @deviceId
              @_presence =  mobileDevice.location.atHome
              @_relativeDistance = (1-mobileDevice.location.relativeDistanceFromHomeFence) * 100
              @emit "presence", @_presence
              @emit "relativeDistance", @_relativeDistance
          Promise.resolve(mobileDevices)
        .catch (err) =>
          env.logger.error(err.error_description || (err.code || err))
          if @config.debug
            env.logger.debug("homeId= #{plugin.home.id}")
          Promise.reject(err)

    getPresence: -> Promise.resolve(@_presence)
    getRelativeDistance: -> Promise.resolve(@_relativeDistance)

  class TadoActionProvider extends env.actions.ActionProvider

    constructor: (@framework) ->

    parseAction: (input, context) =>

      tadoDevice = null
      @value = null
      @valueStringVar = null

      tadoDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => device.config.class == "TadoClimate"
      ).value()

      setCommand = (command) =>
        @command = command

      setTemp = (m,tokens) =>
        unless tokens>=15 and tokens<=25
          context?.addError("Temperature must be >=15°C and <=25°C")
          return
        setCommand("temperature")
        @value = Number tokens

      tempString = (m,tokens) =>
        unless tokens?
          context?.addError("No variable")
          return
        @valueStringVar = tokens
        setCommand("temperature")
        return

      m = M(input, context)
        .match('tado ')
        .matchDevice(tadoDevices, (m, d) ->
          # Already had a match with another device?
          if tadoDevice? and tadoDevice.id isnt d.id
            context?.addError(""""#{input.trim()}" is ambiguous.""")
            return
          tadoDevice = d
        )
        .or([
          ((m) =>
            return m.match(' on', (m) =>
              setCommand('power')
              @value = true
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' off', (m) =>
              setCommand('power')
              @value = false
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' auto', (m) =>
              setCommand('mode')
              @value = 'auto'
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' set ')
              .or([
                ((m) =>
                  return m.matchNumber(setTemp)
                ),
                ((m) =>
                  return m.matchVariable(tempString)
                )
              ])
          )
        ])

      match = m.getFullMatch()
      if match? #m.hadMatch()
        env.logger.debug "Rule matched: '", match, "' and passed to Action handler"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new TadoActionHandler(@framework, tadoDevice, @command, @value, @valueStringVar)
        }
      else
        return null


  class TadoActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @tadoDevice, @command, @value, @valueStringVar) ->

    executeAction: (simulate) =>
      if simulate
        return __("would have controlled tado \"%s\"", "")
      else
        if @valueStringVar?
          _var = @valueStringVar.slice(1) if @valueStringVar.indexOf('$') >= 0
          _value = @framework.variableManager.getVariableValue(_var)
        else
          _value = @value

        @tadoDevice.execute(@command, _value)
        .then(()=>
          return __("\"%s\" Rule executed", @command)
        ).catch((err)=>
          return __("\"%s\" Rule not executed", "")
        )


  return plugin
