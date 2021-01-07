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
              env.logger.info("Connected to #{home_info.homes[0].name} with id: #{home_info.homes[0].id}") if home_info.homes[0]?.name?
              if @config.debug
                env.logger.debug(JSON.stringify(home_info))
              @setHome(home_info.homes[0])
              connected
          .catch (err) ->
            env.logger.error("Could not connect to tado web interface: #{(err.error_description || (err.code || err) )}")
            Promise.reject err
      #
      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("TadoThermostat", {
        configDef: deviceConfigDef.TadoThermostat,
        createCallback: (config, lastState) =>
          device = new TadoThermostat(config, lastState,@framework)
          return device
      })

      @framework.deviceManager.registerDeviceClass("TadoPresence", {
        configDef: deviceConfigDef.TadoPresence,
        createCallback: (config, lastState) =>
          device = new TadoPresence(config, lastState,@framework)
          return device
      })

      @framework.ruleManager.addActionProvider(new TadoActionProvider(@framework))

      @framework.on "after init", =>
        # Check if the mobile-frontend was loaded and get a instance
        mobileFrontend = @framework.pluginManager.getPlugin 'mobile-frontend'
        if mobileFrontend?
          mobileFrontend.registerAssetFile 'js', 'pimatic-tado-reloaded/ui/tado.coffee'
          mobileFrontend.registerAssetFile 'css', 'pimatic-tado-reloaded/ui/tado.css'
          mobileFrontend.registerAssetFile 'html', 'pimatic-tado-reloaded/ui/tado.jade'
          #mobileFrontend.registerAssetFile 'js', 'pimatic-tado-reloaded/ui/vendor/spectrum.js'
          #mobileFrontend.registerAssetFile 'css', 'pimatic-tado-reloaded/ui/vendor/spectrum.css'
          #mobileFrontend.registerAssetFile 'js', 'pimatic-tado-reloaded/ui/vendor/async.js'
        else
          env.logger.warn 'your plugin could not find the mobile-frontend. No gui will be available'

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
                  class: 'TadoThermostat'
                  id: id
                  zone: zone.id
                  name: zone.name
                  interval: 120000
                @framework.deviceManager.discoveredDevice(
                  'TadoThermostat', config.name, config)
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

  class TadoThermostat extends env.devices.TemperatureSensor

    template: "tadothermostat"
    actions:
      changePowerTo:
        params:
          power:
            type: "boolean"
      changeProgramTo:
        params:
          program:
            type: "string"
      changeTemperatureTo:
        params:
          temperatureSetpoint:
            type: "number"
      changeTemperatureRoomTo:
        params:
          temperature:
            type: "number"
      changeHumidityRoomTo:
        params:
          humidity:
            type: "number"
      changeTemperatureOutdoorTo:
        params:
          temperature:
            type: "number"
      changeHumidityOutdoorTo:
        params:
          humidity:
            type: "number"

    constructor: (@config, lastState, @framework) ->
      @id = @config.id
      @name = @config.name
      
      @zone = @config.zone
      @supportedModes = []
      @supportedModes.push "heat" if @config.heating

      @_temperatureSetpoint = lastState?.temperatureSetpoint?.value or 20
      @_mode = lastState?.mode?.value or "heat"
      @_power = lastState?.power?.value or true
      @_presence = lastState?.presence?.value or "home"
      @_relativeDistance = lastState?.relativeDistance?.value
      #@_eco = lastState?.eco?.value or false
      @_program = lastState?.program?.value or "auto"
      @_temperatureRoom = lastState?.temperatureRoom?.value or 20
      @_humidityRoom = lastState?.humidityRoom?.value or 50
      #@_temperatureOutdoor = lastState?.temperatureOutdoor?.value or 20
      #@_humidityOutdoor = lastState?.humidityOutdoor?.value or 50
      #@_timeToTemperatureSetpoint = lastState?.timeToTemperatureSetpoint?.value or 0
      #@_battery = lastState?.battery?.value or "ok"
      @_synced = plugin.home?.id?
      @_active = false
      #@_heater = lastState?.heater?.value or false
      #@_cooler = lastState?.cooler?.value or false
      #@temperatureRoomSensor = false
      #@humidityRoomSensor = false
      #@temperatureOutdoorSensor = false
      #@humidityOutdoorSensor = false
      @minThresholdCelsius = @config.minThresholdCelsius ? 5
      @maxThresholdCelsius = @config.maxThresholdCelsius ? 30


      @attributes =
        presence:
          description: "Away or Home presence"
          type: "string"
          label: "Presence"
          unit: ""
          hidden: true
        relativeDistance:
          description: "Relative distance of human/device from home"
          type: "number"
          acronym: "dist"
          unit: '%'
          hidden: true
        temperatureSetpoint:
          description: "The temp that should be set"
          type: "number"
          label: "Temperature Setpoint"
          unit: "°C"
          hidden: true
        power:
          description: "The power mode"
          type: "boolean"
          hidden: true
        program:
          description: "The program mode"
          type: "string"
          enum: ["manual", "auto"]
          default: ["manual"]
          hidden: true
        active:
          description: "If heating or cooling is active"
          type: "boolean"
          labels: ["active","ready"]
          acronym: "status"
          hidden: true
        timeToTemperatureSetpoint:
          description: "The time to reach the temperature setpoint"
          type: "number"
          unit: "sec"
          acronym: "time to setpoint"
          hidden: true
        temperatureRoom:
          description: "The room temperature of the thermostat"
          type: "number"
          acronym: "T"
          unit: "°C"
        humidityRoom:
          description: "The room humidity of the thermostat"
          type: "number"
          acronym: "H"
          unit: "%"
        battery:
          description: "Battery status"
          type: "string"
          #enum: ["ok", "low"]
          hidden: true
        synced:
          description: "Pimatic and tado thermostat are synced"
          type: "boolean"
          acronym: "thermostat"
          labels: ["connected","not connected"]

      @requestClimate()
      @requestClimateIntervalId =
        setInterval( () => 
          @requestClimate()
          @requestPresence()
        , @config.interval)

      super()

    getTemplateName: -> "tadothermostat"

    requestClimate: ->
      env.logger.debug "Start requestClimate " + plugin.loginPromise  #+ ", home.id: " + plugin.home.id
      if plugin.loginPromise? and plugin.home?.id
        plugin.loginPromise
        .then (success) =>
          #env.logger.debug "loginPromise: home.id: " + (plugin.home.id) + ", zone: " + @zone
          return plugin.client.state(plugin.home.id, @zone)
        .then (state) =>
          #env.logger.debug "debug: " + plugin.config.debug + ", state received: "+ JSON.stringify(state,null,2)        
          if plugin.config.debug
            env.logger.debug("state debug received: #{JSON.stringify(state)}")
          @handleState(state)
          Promise.resolve(state)
        .catch (err) =>
          env.logger.error(err.error_description || (err.code || err) )
          if @config.debug
            env.logger.debug("homeId=:" + plugin.home.id)
          Promise.reject(err)

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


    handleState:(state)=>
      if state.sensorDataPoints?.insideTemperature?
        @_setTemperatureRoom(state.sensorDataPoints.insideTemperature.celsius)
      if state.sensorDataPoints?.humidity?
        @_setHumidityRoom(state.sensorDataPoints.humidity.percentage)
      if state.setting.temperature?.celsius?
        @_setSetpoint(state.setting.temperature.celsius)
      if state.setting.power?
        if state.setting.power is "ON"
          @_setPower(true)
        else 
          @_setPower(false)
      if state.overlay? and state.overlayType is "MANUAL"
        @_setProgram('manual')
      else
        @_setProgram('auto')

    #getMode: () -> Promise.resolve(@_mode)
    getPower: () -> Promise.resolve(@_power)
    #getEco: () -> Promise.resolve(@_eco)
    getProgram: () -> Promise.resolve(@_program)
    getTemperatureSetpoint: () -> Promise.resolve(@_temperatureSetpoint)
    #getTemperatureSetpointLow: () -> Promise.resolve(@_temperatureSetpointLow)
    #getTemperatureSetpointHigh: () -> Promise.resolve(@_temperatureSetpointHigh)
    getActive: () -> Promise.resolve(@_active)
    #getHeater: () -> Promise.resolve(@_heater)
    #getCooler: () -> Promise.resolve(@_cooler)
    getTemperatureRoom: () -> Promise.resolve(@_temperatureRoom)
    getHumidityRoom: () -> Promise.resolve(@_humidityRoom)
    #getTemperatureOutdoor: () -> Promise.resolve(@_temperatureOutdoor)
    #getHumidityOutdoor: () -> Promise.resolve(@_humidityOutdoor)
    getTimeToTemperatureSetpoint: () -> Promise.resolve(@_timeToTemperatureSetpoint)
    getBattery: () -> Promise.resolve(@_battery)
    getSynced: () -> Promise.resolve(@_synced)
    getPresence: () -> Promise.resolve @_presence
    getRelativeDistance: () -> Promise.resolve @_relativeDistance

    powerTxt:(power)=>
      if power then return "ON" else return "OFF"
           
    upperCaseFirst = (string) ->
      unless string.length is 0
        string[0].toUpperCase() + string.slice(1)
      else ""

    _setMode: (mode) ->
      if mode is @_mode then return
      @_mode = mode
      @emit "mode", @_mode

    _setPower: (power) ->
      if power is @_power then return
      @_power = power
      @handleTemperatureChange()
      @emit "power", @_power

    _setEco: (eco) ->
      if eco is @_eco then return
      @_eco = eco
      @emit "eco", @_eco

    _setProgram: (program) ->
      if program is @_program then return
      @_program = program
      @emit "program", @_program

    _setSynced: (synced) ->
      if synced is @_synced then return
      @_synced = synced
      @emit "synced", @_synced

    _setSetpoint: (temperatureSetpoint) ->
      if temperatureSetpoint is @_temperatureSetpoint then return
      @_temperatureSetpoint = temperatureSetpoint
      @emit "temperatureSetpoint", @_temperatureSetpoint

    _setSetpointLow: (temperatureSetpoint) ->
      if temperatureSetpoint is @_temperatureSetpointLow then return
      @_temperatureSetpointLow = temperatureSetpoint
      @emit "temperatureSetpointLow", @_temperatureSetpointLow

    _setSetpointHigh: (temperatureSetpoint) ->
      if temperatureSetpoint is @_temperatureSetpointHigh then return
      @_temperatureSetpointHigh = temperatureSetpoint
      @emit "temperatureSetpointHigh", @_temperatureSetpointHigh

    _setHeater: (heater) ->
      if heater is @_heater then return
      @_heater = heater
      @emit "heater", @_heater

    _setCooler: (cooler) ->
      if cooler is @_cooler then return
      @_cooler = cooler
      @emit "cooler", @_cooler

    _setBattery: (battery) ->
      if battery is @_battery then return
      @_battery = battery
      @emit "battery", @_battery

    _setActive: (active) ->
      #if active is @_active then return
      @_active = active
      @emit "active", @_active

    _setTimeToTemperatureSetpoint: (time) ->
      if time is @_timeToTemperatureSetpoint then return
      @_timeToTemperatureSetpoint = time
      @emit "timeToTemperatureSetpoint", @_timeToTemperatureSetpoint

    _setTemperatureRoom: (temperatureRoom) ->
      if temperatureRoom is @_temperatureRoom then return
      @_temperatureRoom = temperatureRoom
      @emit "temperatureRoom", @_temperatureRoom

    _setHumidityRoom: (humidityRoom) ->
      if humidityRoom is @_humidityRoom then return
      @_humidityRoom = humidityRoom
      @emit "humidityRoom", @_humidityRoom

    _setTemperatureOutdoor: (temperatureOutdoor) ->
      if temperatureOutdoor is @_temperatureOutdoor then return
      @_temperatureOutdoor = temperatureOutdoor
      @emit "temperatureOutdoor", @_temperatureOutdoor

    _setHumidityOutdoor: (humidityOutdoor) ->
      if humidityOutdoor is @_humidityOutdoor then return
      @_humidityOutdoor = humidityOutdoor
      @emit "humidityOutdoor", @_humidityOutdoor

    changeModeTo: (mode) ->
      if mode in @supportedModes
        @_setMode(mode)
      else
        env.logger.info "Mode '#{mode}' is not supported"
      return Promise.resolve()

    changeProgramTo: (program) ->
      if plugin.home?.id?
        @_setProgram(program)
        switch program
          when "auto"
            plugin.client.setAuto(plugin.home.id, @zone)
            .then((res)=>
              env.logger.debug "Result plugin.client.setAuto: " + JSON.stringify(res,null,2) if res?
              @handleState(res)
              resolve()
            ).catch((err)=>
              env.logger.debug "error setPower: " + JSON.stringify(err,null,2)
            )
          when "manual"
            #setting temperature to current value, disables auto mode and starts manual mode
            @getTemperatureSetpoint()
            .then (temperature)=>
              @changeTemperatureTo(temperature)
      else
        env.logger.info "Home not ready!"
      return Promise.resolve()

    changePowerTo: (power) ->
      if plugin.home?.id?
        @_setPower(power)
        plugin.client.setState(plugin.home.id, @zone, @powerTxt(power), @_temperatureSetpoint)
        .then((res)=>
          env.logger.debug "Result plugin.client.setPower: " + JSON.stringify(res,null,2) if res?
          @handleState(res)
          resolve()
        ).catch((err)=>
          env.logger.debug "error setPower: " + JSON.stringify(err,null,2)
        )
      else
        env.logger.info "Home not ready!"
      return Promise.resolve()

    toggleEco: () ->
      if plugin.home?.id?
        @_setEco(!@_eco)
      else
        env.logger.info "Home not ready!"
      return Promise.resolve()

    changeEcoTo: (eco) ->
      if plugin.home?.id?
        @_setEco(eco)
      else
        env.logger.info "Home not ready!"
      return Promise.resolve()

    changeActiveTo: (active) ->
      @_setActive(active)
      return Promise.resolve()

    changeHeaterTo: (heater) ->
      @_setHeater(heater)
      @_setActive(heater)
      return Promise.resolve()
    changeCoolerTo: (cooler) ->
      @_setCooler(cooler)
      @_setActive(cooler)
      return Promise.resolve()

    changeTimeToTemperatureSetpointTo: (time) ->
      @_setTimeToTemperatureSetpoint(time)
      return Promise.resolve()

    changeTemperatureRoomTo: (temperatureRoom) ->
      @_setTemperatureRoom(temperatureRoom)
      @handleTemperatureChange()
      return Promise.resolve()

    changeHumidityRoomTo: (humidityRoom) ->
      @_setHumidityRoom(humidityRoom)
      return Promise.resolve()

    changeTemperatureOutdoorTo: (temperatureOutdoor) ->
      @_setTemperatureOutdoor(temperatureOutdoor)
      @handleTemperatureChange()
      return Promise.resolve()

    changeHumidityOutdoorTo: (humidityOutdoor) ->
      @_setHumidityOutdoor(humidityOutdoor)
      return Promise.resolve()

    changeTemperatureTo: (_temperatureSetpoint) ->
      if plugin.home?.id?
        temperatureSetpoint = Math.round(10*_temperatureSetpoint)/10
        if temperatureSetpoint >= @minThresholdCelsius and temperatureSetpoint <= @maxThresholdCelsius
          plugin.client.setState(plugin.home.id, @zone, @powerTxt(@_power), temperatureSetpoint)
          .then((res)=>
            env.logger.debug "Temperature set: " + JSON.stringify(res,null,2) if res?
            @_setSetpoint(temperatureSetpoint)
            @handleState(res)
          ).catch((err)=>
            env.logger.debug "error setTemperature: " + JSON.stringify(err,null,2)
          )
        else
          env.logger.info "SetPoint '#{temperatureSetpoint}' is out of range: #{@minThresholdCelsius}-#{@maxThresholdCelsius}"
      else
        env.logger.info "Home not ready!"
      return Promise.resolve()

    changeTemperatureLowTo: (_temperatureSetpoint) ->
      temperatureSetpoint = Math.round(10*_temperatureSetpoint)/10
      @getMode()
      .then (mode)=>
        if mode is "heatcool"
          @_setSetpointLow(temperatureSetpoint)
          @handleTemperatureChange()
        else
          env.logger.info "SetpointLow can only be set in 'heatcool' mode!"
      return Promise.resolve()

    changeTemperatureHighTo: (_temperatureSetpoint) ->
      temperatureSetpoint = Math.round(10*_temperatureSetpoint)/10
      @getMode()
      .then (mode)=>
        if mode is "heatcool"
          @_setSetpointHigh(temperatureSetpoint)
          @handleTemperatureChange()
        else
          env.logger.info "SetpointHigh can only be set in 'heatcool' mode!"
      return Promise.resolve()

    handleTemperatureChange: () =>
      # check if pid -> enable pid
      return
      ###
      @getPower()
      .then((power)=>
        if power
          @getMode()
          .then((mode)=>
            switch mode
              when "heat"
                @changeCoolerTo(off)
                if @_temperatureSetpoint > @_temperatureRoom
                  @changeHeaterTo(on)
                else
                  @changeHeaterTo(off)
              when "cool"
                @changeHeaterTo(off)
                if @_temperatureSetpoint < @_temperatureRoom
                  @changeCoolerTo(on)
                else
                  @changeCoolerTo(off)
              when "heatcool"
                if @_temperatureSetpointLow > @_temperatureRoom
                  @changeHeaterTo(on)
                else
                  @changeHeaterTo(off)
                if @_temperatureSetpointHigh < @_temperatureRoom
                  @changeCoolerTo(on)
                else
                  @changeCoolerTo(off)
        )
        else
          @changeHeaterTo(off)
          @changeCoolerTo(off)
      )
      ###

    execute: (device, command, options) =>
      env.logger.debug "Execute command: #{command} with options: " + JSON.stringify(options,null,2)
      return new Promise((resolve, reject) =>
        unless device?
          env.logger.info "Device '#{@name}' is unknown"
          return reject()
        switch command
          when "heat"
            @changeModeTo("heat")
          when "heatcool"
            @changeModeTo("heatcool")
          when "cool"
            @changeModeTo("cool")
          when "eco"
            @changeEcoTo(true)
          when "off"
            @changePowerTo(false)
          when "on"
            @changePowerTo(true)
          when "setpoint"
            if options.variable
              _setpoint = @framework.variableManager.getVariableValue(options.setpoint.replace("$",""))
            else
              _setpoint = options.setpoint
            @changeTemperatureTo(_setpoint)
          when "setpointlow"
            if options.variable
              _setpointLow = @framework.variableManager.getVariableValue(options.setpointLow.replace("$",""))
            else
              _setpointLow = options.setpointLow
            @changeTemperatureLowTo(_setpointLow)
          when "setpointhigh"
            if options.variable
              _setpointHigh = @framework.variableManager.getVariableValue(options.setpointHigh.replace("$",""))
            else
              _setpointHigh = options.setpointHigh
            @changeTemperatureHighTo(options.setpointHigh)
          when "manual"
            @changeProgramTo("manual")
          when "auto"
            @changeProgramTo("auto")
          else
            env.logger.debug "Unknown command received: " + command
            reject()
      )

    destroy: ->
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

      @tadoThermostatDevice = null

      @command = ""

      @parameters = {}

      tadoThermostatDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => device.config.class == "TadoThermostat"
      ).value()

      setCommand = (_command) =>
        @command = _command

      setpoint = (m,tokens) =>
        unless tokens >= @tadoThermostatDevice.config.minThresholdCelsius and tokens <= @tadoThermostatDevice.config.maxThresholdCelsius
          context?.addError("Setpoint must be between #{@tadoThermostatDevice.config.minThresholdCelsius} and #{@tadoThermostatDevice.config.maxThresholdCelsius}")
          return
        setCommand("setpoint")
        @parameters["setpoint"] = Number tokens
        @parameters["variable"] = false
      setpointVar = (m,tokens) =>
        setCommand("setpoint")
        @parameters["setpoint"] = tokens
        @parameters["variable"] = true

      setpointLow = (m,tokens) =>
        unless tokens >= @tadoThermostatDevice.config.minThresholdCelsius and tokens <= @tadoThermostatDevice.config.maxThresholdCelsius
          context?.addError("Setpoint must be between #{@tadoThermostatDevice.config.minThresholdCelsius} and #{@tadoThermostatDevice.config.maxThresholdCelsius}")
          return
        setCommand("setpointlow")
        @parameters["setpointLow"] = Number tokens
      setpointLowVar = (m,tokens) =>
        setCommand("setpointlow")
        @parameters["setpointLow"] = tokens
        @parameters["variable"] = true

      setpointHigh = (m,tokens) =>
        unless tokens >= @tadoThermostatDevice.config.minThresholdCelsius and tokens <= @tadoThermostatDevice.config.maxThresholdCelsius
          context?.addError("Setpoint must be between #{@tadoThermostatDevice.config.minThresholdCelsius} and #{@tadoThermostatDevice.config.maxThresholdCelsius}")
          return
        setCommand("setpointhigh")
        @parameters["setpointHigh"] = Number tokens
      setpointHighVar = (m,tokens) =>
        setCommand("setpointhigh")
        @parameters["setpointHigh"] = tokens
        @parameters["variable"] = true

      m = M(input, context)
        .match('tado ')
        .matchDevice(tadoThermostatDevices, (m, d) =>
          # Already had a match with another device?
          if tadoThermostatDevice? and tadoThermostatDevice.config.id isnt d.config.id
            context?.addError(""""#{input.trim()}" is ambiguous.""")
            return
          @tadoThermostatDevice = d
        )
        .or([
          ((m) =>
            return m.match(' heat', (m)=>
              setCommand('heat')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' heatcool', (m)=>
              setCommand('heatcool')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' cool', (m)=>
              setCommand('cool')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' eco', (m)=>
              setCommand('eco')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' off', (m)=>
              setCommand('off')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' on', (m)=>
              setCommand('on')
              match = m.getFullMatch()
            )
          )
          ((m) =>
            return m.match(' setpoint ')
              .or([
                ((m) =>
                  m.matchNumber(setpoint)
                ),
                ((m) =>
                  m.matchVariable(setpointVar)
                )
              ])
          ),
          ((m) =>
            return m.match(' setpoint low ')
              .or([
                ((m) =>
                  m.matchNumber(setpointLow)
                ),
                ((m) =>
                  m.matchVariable(setpointLowVar)
                )
              ])
          ),
          ((m) =>
            return m.match(' setpoint high ')
              .or([
                ((m) =>
                  m.matchNumber(setpointHigh)
                ),
                ((m) =>
                  m.matchVariable(setpointHighVar)
                )
              ])
          ),
          ((m) =>
            return m.match(' auto', (m)=>
              setCommand('auto')
              match = m.getFullMatch()
            )
          ),
          ((m) =>
            return m.match(' manual', (m)=>
              setCommand('manual')
              match = m.getFullMatch()
            )
          ),
        ])

      match = m.getFullMatch()
      if match?
        env.logger.debug "Rule matched: '", match, "' and passed to Action handler"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new TadoThermostatActionHandler(@framework, @tadoThermostatDevice, @command, @parameters)
        }
      else
        return null

  class TadoThermostatActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @tadoThermostatDevice, @command, @parameters) ->

    executeAction: (simulate) =>
      if simulate
        return __("would have cleaned \"%s\"", "")
      else
        @tadoThermostatDevice.execute(@tadoThermostatDevice, @command, @parameters)
        .then(()=>
          return __("\"%s\" Rule executed", @command)
        ).catch((err)=>
          return __("\"%s\" Rule not executed", JSON.stringify(err))
        )




  return plugin
