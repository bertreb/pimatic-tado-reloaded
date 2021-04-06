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
      #@framework.on "after init", =>
      #  env.logger.info("Pimatic server started, initializing tado connection") 
      #  #connecting to tado web interface and acquiring home id  
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
            @emit 'connected'
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

    attributes:
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
      percentage:
        description: "The heating percentage"
        type: "number"
        acronym: "heating"
        label: "Heating percentage"
        unit: "%"
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
      connected:
        description: "Pimatic and tado thermostat are synced"
        type: "boolean"
        acronym: "thermostat"
        labels: ["connected","not connected"]


    constructor: (@config, lastState, @framework) ->
      @id = @config.id
      @name = @config.name

      @deviceId = @config.deviceId
      
      @zone = @config.zone
      #@supportedModes = []
      #@supportedModes.push "heat" if @config.heating

      @interval = @config.interval ? 120000
      @toAutoTime = @config.toAutoTime ? 0 # seconds for timer switching manual back to auto

      @_temperatureSetpoint = lastState?.temperatureSetpoint?.value or 20
      @_mode = lastState?.mode?.value or "heat"
      @_power = lastState?.power?.value or true
      @_presence = lastState?.presence?.value or "home"
      @_relativeDistance = lastState?.relativeDistance?.value
      #@_eco = lastState?.eco?.value or false
      @_program = lastState?.program?.value or "auto"
      @_temperatureRoom = lastState?.temperatureRoom?.value or 20
      @_humidityRoom = lastState?.humidityRoom?.value or 50
      @_percentage = lastState?.percentage?.value or 0
      #@_humidityOutdoor = lastState?.humidityOutdoor?.value or 50
      #@_timeToTemperatureSetpoint = lastState?.timeToTemperatureSetpoint?.value or 0
      #@_battery = lastState?.battery?.value or "ok"
      @_connected = plugin.home?.id?
      #@_active = true
      #@_heater = lastState?.heater?.value or false
      #@_cooler = lastState?.cooler?.value or false
      #@temperatureRoomSensor = false
      #@humidityRoomSensor = false
      #@temperatureOutdoorSensor = false
      #@humidityOutdoorSensor = false
      @minThresholdCelsius = @config.minThresholdCelsius ? 5
      @maxThresholdCelsius = @config.maxThresholdCelsius ? 30

      @requestingClimate = () =>
        @requestClimate()
        @requestClimateTimer =
          setTimeout( () =>
            @requestingClimate()
          , @interval)

      plugin.on 'connected', @pluginListener =  ()=>
        env.logger.debug 'Tado conencted to cloud, start status update cycle'
        @_setConnected(true)
        @requestingClimate()

      @framework.variableManager.waitForInit()
      .then ()=>
        @requestingClimate()        


      super()

    getTemplateName: -> "tadothermostat"

    requestClimate: ->
      #env.logger.debug "Start requestClimate " + plugin.loginPromise  + ", home.id: " + plugin.home.id
      if plugin.loginPromise? and plugin.home?.id
        plugin.loginPromise
        .then (success) =>
          env.logger.debug "logged in: home.id: " + (plugin.home.id) + ", zone: " + @zone
          return plugin.client.state(plugin.home.id, @zone)
        .then (state) =>
          #env.logger.debug "debug: " + plugin.config.debug + ", state received: "+ JSON.stringify(state,null,2)        
          if plugin.config.debug
            env.logger.debug("state received, processing state") #: #{JSON.stringify(state)}")
          @handleState(state)
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
          Promise.resolve()
        .catch (err) =>
          env.logger.error(err.error_description || (err.code || err) )
          if @config.debug
            env.logger.debug("homeId=:" + plugin.home.id)
          Promise.reject(err)

    handleState:(state)=>
      if state.sensorDataPoints?.insideTemperature?
        @_setTemperatureRoom(state.sensorDataPoints.insideTemperature.celsius)
      if state.sensorDataPoints?.humidity?
        @_setHumidityRoom(state.sensorDataPoints.humidity.percentage)
      if state.setting.temperature?.celsius?
        @_setSetpoint(state.setting.temperature.celsius)
      if state.activityDataPoints?.heatingPower?.percentage?
        @_setPercentage(state.activityDataPoints.heatingPower.percentage)
      #env.logger.debug("state.termination.type: " + state.termination.type) if state.termination?.type?
      if state.setting.power?
        if state.setting.power is "ON"
          @_setPower(true)
        else 
          @_setPower(false)
      if (state.overlay? and state.overlayType is "MANUAL") or 
        (state.termination?.type? and state.termination.type is "MANUAL") or
          (state.termination?.type? and state.termination.type is "TIMER")
        @_setProgram('manual')
      else
        @_setProgram('auto')

    getPower: () -> Promise.resolve(@_power)
    getProgram: () -> Promise.resolve(@_program)
    getTemperatureSetpoint: () -> Promise.resolve(@_temperatureSetpoint)
    getTemperatureRoom: () -> Promise.resolve(@_temperatureRoom)
    getPercentage: () -> Promise.resolve(@_percentage)
    getHumidityRoom: () -> Promise.resolve(@_humidityRoom)
    getConnected: () -> Promise.resolve(@_connected)
    getPresence: () -> Promise.resolve @_presence
    getRelativeDistance: () -> Promise.resolve @_relativeDistance

    powerTxt:(power)=>
      if power then return "ON" else return "OFF"
           
    upperCaseFirst = (string) ->
      unless string.length is 0
        string[0].toUpperCase() + string.slice(1)
      else ""

    _setPower: (power) ->
      if power is @_power then return
      @_power = power
      @handleTemperatureChange()
      @emit "power", @_power

    _setProgram: (program) ->
      _program = program.toLowerCase()
      if _program is @_program then return
      @_program = _program
      @emit "program", @_program

    _setConnected: (connected) ->
      if connected is @_connected then return
      @_connected = connected
      @emit "connected", @_connected

    _setSetpoint: (temperatureSetpoint) ->
      if temperatureSetpoint is @_temperatureSetpoint then return
      @_temperatureSetpoint = temperatureSetpoint
      @emit "temperatureSetpoint", @_temperatureSetpoint

    _setTemperatureRoom: (temperatureRoom) ->
      if temperatureRoom is @_temperatureRoom then return
      @_temperatureRoom = temperatureRoom
      @emit "temperatureRoom", @_temperatureRoom

    _setHumidityRoom: (humidityRoom) ->
      if humidityRoom is @_humidityRoom then return
      @_humidityRoom = humidityRoom
      @emit "humidityRoom", @_humidityRoom

    _setPercentage: (percentage) ->
      if percentage is @_percentage then return
      @_percentage = percentage
      @emit "percentage", @_percentage

    changeProgramTo: (program) ->
      if plugin.home?.id?
        _program = program.toLowerCase()
        @_setPower(on)
        @_setSetpoint(@_temperatureSetpoint)
        switch _program
          when "auto"
            plugin.client.setAuto(plugin.home.id, @zone)
            .then(()=>
              @_setProgram(program)
              clearTimeout @requestClimateTimer if @requestClimateTimer?
              @requestClimate()
            ).catch((err)=>
              env.logger.debug "error changeProgram: " + JSON.stringify(err,null,2)
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
        env.logger.debug "changePowerTo: " + power
        if power
          @changeProgramTo('auto') unless @_program is 'auto'
        else
          data =
            setting:
              type: "HEATING"
              power: @powerTxt(off)
              temperature: 
                celsius: String @_temperatureSetpoint
          env.logger.debug "Power #{power} " + JSON.stringify(data,null,2)
          plugin.client.setState(plugin.home.id, @zone, data) #@powerTxt(power), @_temperatureSetpoint)
          .then((res)=>
            env.logger.debug "Result plugin.client.setPower: " + JSON.stringify(res,null,2) if res?
            @handleState(res) if res?
            @_setPower(power)
          ).catch((err)=>
            env.logger.debug "error setPower: " + JSON.stringify(err,null,2)
          )
      else
        env.logger.info "Home not ready!"
      return Promise.resolve()


    changeTemperatureTo: (_temperatureSetpoint) ->
      if plugin.home?.id?
        @_setPower(on)
        @_setProgram("manual")
        temperatureSetpoint = Math.round(10*_temperatureSetpoint)/10
        if temperatureSetpoint >= @minThresholdCelsius and temperatureSetpoint <= @maxThresholdCelsius
          data =
            setting:
              type: "HEATING"
              power: @powerTxt(@_power)
              temperature: 
                celsius: _temperatureSetpoint
          if @toAutoTime
            data["termination"] =
              type: "TIMER"
              durationInSeconds: @toAutoTime
          else
            data["termination"] =
              type: "MANUAL"
          plugin.client.setState(plugin.home.id, @zone, data)
          .then((res)=>
            env.logger.debug "Temperature set: " + JSON.stringify(res,null,2) if res?
            @_setSetpoint(temperatureSetpoint)
            @handleState(res)
            if @toAutoTime
              clearTimeout @requestClimateTimer if @requestClimateTimer?
              @requestClimateTimer = setTimeout( ()=>
                @requestingClimate()
              , (@toAutoTime * 1000) + 2000)
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
          when "manual"
            @changeProgramTo("manual")
          when "auto"
            @changeProgramTo("auto")
          else
            env.logger.debug "Unknown command received: " + command
            reject()
      )

    destroy: ->
      clearTimeout @requestClimateTimer if @requestClimateTimer?
      plugin.removeListener 'connected', @pluginListener
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
            if mobileDevice.id == @deviceId and mobileDevice.location?.atHome?
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
