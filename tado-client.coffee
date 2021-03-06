module.exports = (env) ->

  class Client

    request = env.require('request') #needle?
    moment = env.require('moment')
    BASE_URL = 'https://my.tado.com'
    AUTH_URL = 'https://auth.tado.com'
    CLIENT_ID = 'tado-web-app'
    CLIENT_SECRET = 'wZaRN7rpjn3FoNyF5IFuxg9uMzYJcvOoQ8QWiIqS3hfk6gLhVlG57j5YNoZL2Rtc'
    REFERER = 'https://my.tado.com/'

    constructor: () ->

    login:(username,password) ->
      return new Promise( (resolve, reject) =>
        request.post(
          url: AUTH_URL + '/oauth/token'
          qs:
            client_id: CLIENT_ID
            client_secret: CLIENT_SECRET
            grant_type: 'password'
            password: password
            username: username
            scope: 'home.user'
          json: true
        , (err, response, result) =>
          if (err || response.statusCode != 200)
            reject(err || result)
          else
            this.saveToken(result)
            resolve(true)
          )
      )

    saveToken:(token) ->
      this.token = token
      this.token.expires_in =
        moment().add(token.expires_in - 30, 'seconds').toDate()

    refreshToken:() ->
      return new Promise((resolve, reject) =>
        if (!this.token)
          return reject(new Error('not logged in'))
        if (moment().subtract(5, 'seconds').isBefore(this.token.expires_in))
          return resolve()
        request.post(
          url: AUTH_URL + '/oauth/token'
          qs:
            client_id: CLIENT_ID
            client_secret: CLIENT_SECRET
            grant_type: 'refresh_token'
            refresh_token: this.token.refresh_token
            scope: 'home.user'
          json: true
        , (err, response, result) =>
          if (err || response.statusCode != 200)
            reject(err || result)
          else
            this.saveToken(result)
            resolve(true)
        )
      )

    api:(path) ->
      return this.refreshToken().then(() =>
        return new Promise((resolve, reject) =>
          request.get(
            url: BASE_URL + '/api/v2' + path
            json: true
            headers:
              referer: REFERER
            auth:
              bearer: this.token.access_token
          , (err, response, result) ->
            if (err || response.statusCode != 200)
              reject(err || result)
            else
              resolve(result)
          )
        )
      )

    apiSet:(path, data) ->
      return this.refreshToken().then(() =>
        return new Promise((resolve, reject) =>
          request.put(
            url: BASE_URL + '/api/v2' + path
            json: true
            headers:
              referer: REFERER
            auth:
              bearer: this.token.access_token
            body: data
          , (err, response, result) ->
            #console.log("apiset response.statusCode "+JSON.stringify(response,null,2))
            if (err || response.statusCode != 200)
              reject(err || result)
            else
              resolve(result)
          )
        )
      )

    apiDelete:(path) ->
      return this.refreshToken().then(() =>
        #console.log("Path: "+path)
        return new Promise((resolve, reject) =>
          request.delete(
            url: BASE_URL + '/api/v2' + path
            json: true
            headers:
              referer: REFERER
            auth:
              bearer: this.token.access_token
          , (err, response, result) ->
            if (err || !(response.statusCode == 200 || response.statusCode == 204 ))
              reject(err || result)
            else
              resolve(result)
          )
        )
      )


    me:() ->
      return this.api('/me')

    home:(homeId) ->
      return this.api("/homes/#{homeId}")

    zones:(homeId) ->
      return this.api("/homes/#{homeId}/zones")

    weather:(homeId) ->
      return this.api("/homes/#{homeId}/weather")

    state:(homeId, zoneId) ->
      return this.api("/homes/#{homeId}/zones/#{zoneId}/state")

    mobileDevices:(homeId) ->
      return this.api("/homes/#{homeId}/mobileDevices")


    setState:(homeId, zoneId, data) => #pwr, temp) =>
      #console.log("setState data: "+JSON.stringify(data,null,2))
      return this.apiSet("/homes/#{homeId}/zones/#{zoneId}/overlay", data)

    ###
    setTemperature:(homeId, zoneId, temperature) =>
      this.setPoint = temperature
      data =
        setting:
          type: "HEATING"
          power: this.power || "ON"
          temperature: 
            celsius: this.setPoint
            #fahrenheit: Math.round((10 * (this.setPoint * 9/5 + 32)))/10
        termination:
          type: "MANUAL"
      return this.apiSet("/homes/#{homeId}/zones/#{zoneId}/overlay", data)
    ###

    setAuto:(homeId, zoneId) ->
      return this.apiDelete("/homes/#{homeId}/zones/#{zoneId}/overlay")


  return Client
