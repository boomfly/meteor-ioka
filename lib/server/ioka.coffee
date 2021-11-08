import crypto from 'crypto'
import {Meteor} from 'meteor/meteor'
import {WebApp} from 'meteor/webapp'
import {Random} from 'meteor/random'
import {fetch} from 'meteor/fetch'
import {_} from 'meteor/underscore'
import {URL, URLSearchParams} from 'url'

import {getConfig} from './config'
import {SIGNATURE_HEADER_NAME, WEBHOOK_EVENTS} from '../constants'

class Ioka
  constructor: ->
    config = getConfig()
    # Маршруты для обработки REST запросов от Ioka Callback
    pathname = "/api/#{config.callbackPathname}"
    # @_registerHandler pathname

  config: (cfg) ->
    config = getConfig()
    return config unless cfg
    if cfg.callbackPathname and config.callbackPathname isnt cfg.callbackPathname
      pathname = "/api/#{cfg.callbackPathname}"
      @_registerHandler pathname
    Object.assign(config, cfg)

  onNotification: (cb) -> @_onNotification = cb

  createOrder: (params) ->
    config = getConfig()
    siteUrl = config.siteUrl.replace(/\/$/, '')
    params.currency = params.currency or config.currency
    # params.language = params.language or config.language
    await @_request 'orders', params

  # Webhooks
  getWebhooks: (params) -> await @_request 'webhooks', params, 'GET'
  createWebhook: (params) -> await @_request 'webhooks', params
  getWebhookById: (webhookId) -> await @_request "webhooks/#{webhookId}", {}, 'GET'
  deleteWebhookById: (webhookId) -> await @_request "webhooks/#{webhookId}", {}, 'DELETE'
  updateWebhookById: (webhookId, params) -> await @_request "webhooks/#{webhookId}", params, 'PATCH'

  # Private methods

  _request: (pathname, params, method = 'POST') ->
    {isTest, secretKey} = getConfig()
    if isTest
      apiUrl = 'https://stage-api.ioka.kz/v2'
    else
      apiUrl = 'https://api.ioka.kz/v2'
    options = {
      method
      headers: {
        'Content-Type': 'application/json;charset=utf-8'
        'API-KEY': secretKey
      }
    }
    url = new URL("#{apiUrl}/#{pathname}")
    if method.toUpperCase() is 'GET'
      url.search = new URLSearchParams(params).toString()
    else
      options.body = JSON.stringify(params) if params
    response = await fetch url, options
    # console.log 'IokaClient.request', response, response.headers, options
    await response.json()

  _sign: (message, secret) -> crypto.createHmac('sha256', secret).update(message).digest('base64')

  _updateWebhook: (pathname) ->
    config = getConfig()
    pathname = "/api/#{config.callbackPathname}" unless pathname
    url = "#{config.siteUrl}#{pathname}"
    list = await @getWebhooks()
    console.log 'Ioka._updateWebhook list response', list

    if list.code is 'Unauthorized'
      console.error 'Ioka._updateWebhook wrong secret key'
      return Promise.resolve()

    if list.length > 1
      promises = []
      for i in [1..list.length - 1]
        item = list[i]
        promises.push @deleteWebhookById(item.id)
      await Promise.all promises

    if list.length is 0
      response = await @createWebhook {
        url
        events: WEBHOOK_EVENTS
      }
      console.log 'Ioka._updateWebhook create response', response
      return
    
    item = list[0]
    needUpdate = false
    if _.intersection(WEBHOOK_EVENTS, list.events).length > 0
      needUpdate = true
    if item.url isnt url
      needUpdate = true
    if needUpdate
      response = await @updateWebhookById item.id, {
        url
        events: WEBHOOK_EVENTS
      }
      console.log 'Ioka._updateWebhook update response', {response, url}
    return

  _registerHandler: (pathname) ->
    config = getConfig()
    handlerIndex = WebApp.rawConnectHandlers.stack.findIndex (i) => i.handler is @_handler
    if handlerIndex > 0
      WebApp.rawConnectHandlers.stack.splice handlerIndex, 1
    WebApp.rawConnectHandlers.use pathname, @_handler
    if config.secretKey
      @_updateWebhook pathname

  # Webhooks handler
  _handler: (req, res, next) =>
    config = getConfig()
    method = req.method

    console.log 'Ioka.handler method', method, req.url

    if method is 'POST'
      chunksLength = 0
      chunks = []

      body = await new Promise (resolve, reject) ->
        req.on 'data', (chunk) ->
          console.log 'Ioka.handler POST data chunk', chunk
          chunks.push(chunk)
          chunksLength += chunk.length
        req.on 'end', -> resolve Buffer.concat(chunks, chunksLength).toString('utf-8')
        req.on 'error', reject

      unless body
        console.warn 'Ioka.handler: Empty POST body'
        res.writeHead 400
        res.end()
        return

      payload = body
      params = JSON.parse(body)
    else
      url = new URL(Meteor.absoluteUrl(req.url))
      payload = Object.fromEntries(url.searchParams)
      unless payload
        console.warn 'Ioka.handler: Empty GET query'
        res.writeHead 400
        res.end()
        return
      params = url.searchParams.toString()

    console.log 'Ioka.handler', payload, params

    signatureHeader = req.headers[SIGNATURE_HEADER_NAME]

    unless signatureHeader
      console.warn 'Ioka.handler: Request without signature', {[SIGNATURE_HEADER_NAME]: signatureHeader}
      res.setHeader 'Content-Type', 'application/json'
      res.writeHead 401
      res.end()
      return

    signature = @_sign payload, config.secretKey

    if signature isnt signatureHeader
      console.warn 'Ioka.handler: Wrong request signature. Hack possible', {signature, [SIGNATURE_HEADER_NAME]: signatureHeader}
      res.setHeader 'Content-Type', 'application/json'
      res.writeHead 401
      res.end()
      return

    Ioka.onNotification?(params)
    res.writeHead 200
    res.end()

export default Ioka = new Ioka