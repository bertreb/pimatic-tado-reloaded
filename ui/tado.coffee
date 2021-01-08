$(document).on 'templateinit', (event) ->

  # define the item class
  class TadoThermostatItem extends pimatic.DeviceItem

    constructor: (templData, @device) ->
      super(templData, @device)

      # The value in the input
      @inputValue = ko.observable()

      # temperatureSetpoint changes -> update input + also update buttons if needed
      @stAttr = @getAttribute('temperatureSetpoint')
      @inputValue(@stAttr.value())

      attrValue = @stAttr.value()
      @stAttr.value.subscribe( (value) =>
        @inputValue(value)
        attrValue = value
      )

      # input changes -> call changeTemperature
      ko.computed( =>
        textValue = @inputValue()
        if textValue? and attrValue? and parseFloat(attrValue) isnt parseFloat(textValue)
          @changeTemperatureTo(parseFloat(textValue))
      ).extend({ rateLimit: { timeout: 1000, method: "notifyWhenChangesStop" } })

      @synced = @getAttribute('synced').value

    getItemTemplate: => 'tadothermostat'

    afterRender: (elements) =>
      super(elements)

      # find the buttons
      @awayButton = $(elements).find('[name=awayButton]')
      @homeButton = $(elements).find('[name=homeButton]')
      @offButton = $(elements).find('[name=offButton]')
      @onButton = $(elements).find('[name=onButton]')
      @manualButton = $(elements).find('[name=manualButton]')
      @autoButton = $(elements).find('[name=autoButton]')
      @input = $(elements).find('[name=spin]')
      @input.spinbox()

      @updatePowerButtons()
      @updateProgramButtons()
      @updatePresenceButtons()

      @getAttribute('power')?.value.subscribe( => @updatePowerButtons() )
      @getAttribute('program')?.value.subscribe( => @updateProgramButtons() )
      @getAttribute('presence')?.value.subscribe( => @updatePresenceButtons() )
      return

    # define the available actions for the template
    modeOff: -> @changePowerTo false
    modeOn: -> @changePowerTo true
    modeManual: -> @changeProgramTo "manual"
    modeAuto: -> @changeProgramTo "auto"
    setTemp: -> @changeTemperatureTo "#{@inputValue.value()}"

    updatePresenceButtons: =>
      presenceAttr = @getAttribute('presence')?.value()
      switch presenceAttr
        when 'away'
          @awayButton.addClass('ui-btn-active')
          @homeButton.removeClass('ui-btn-active')
        else
          @awayButton.removeClass('ui-btn-active')
          @homeButton.addClass('ui-btn-active')
      return

    updateProgramButtons: =>
      programAttr = @getAttribute('program')?.value()
      switch programAttr
        when 'manual'
          @manualButton.addClass('ui-btn-active')
          @autoButton.removeClass('ui-btn-active')
        when 'auto'
          @manualButton.removeClass('ui-btn-active')
          @autoButton.addClass('ui-btn-active')
      return

    updatePowerButtons: =>
      powerAttr = @getAttribute('power')?.value()
      if powerAttr is false
        @offButton.addClass('ui-btn-active')
        @onButton.removeClass('ui-btn-active')
      else
        @offButton.removeClass('ui-btn-active')
        @onButton.addClass('ui-btn-active')
      return

    changePowerTo: (power) ->
      @device.rest.changePowerTo({power}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

    changeProgramTo: (program) ->
      @device.rest.changeProgramTo({program}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)

    changeTemperatureTo: (temperatureSetpoint) ->
      @input.spinbox('disable')
      @device.rest.changeTemperatureTo({temperatureSetpoint}, global: no)
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)
        .always( => @input.spinbox('enable') )

  # register the item-class
  pimatic.templateClasses['tadothermostat'] = TadoThermostatItem
