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
    @_registerHandler pathname, false

  config: (cfg) ->
    config = getConfig()
    return config unless cfg
    handlerUpdated = false
    if cfg.callbackPathname and config.callbackPathname isnt cfg.callbackPathname
      pathname = "/api/#{cfg.callbackPathname}"
      @_registerHandler pathname
      handlerUpdated = true
    Object.assign(config, cfg)
    # @_updateWebhook() unless handlerUpdated

  onNotification: (cb) -> @_onNotification = cb

  # Orders
  getOrderByExternalId: (externalId) -> await @_request "orders", {external_id: externalId}, 'GET'
  createOrder: (params) ->
    config = @config()
    siteUrl = config.siteUrl.replace(/\/$/, '')
    params.currency = params.currency or config.currency
    # params.language = params.language or config.language
    response = await @_request 'orders', params, 'POST'
    redirectUrl = @_getRedirectUrl response, params
    response.redirectUrl = redirectUrl
    response
  createOrderAccessToken: (orderId) -> await @_request "orders/#{orderId}/access-tokens", 'POST'
  getOrderById: (orderId) -> await @_request "orders/#{orderId}", {}, 'GET'
  getOrderEvents: (orderId) -> await @_request "orders/#{orderId}/events", {}, 'GET'

  # Webhooks
  getWebhooks: (params) -> await @_request 'webhooks', params, 'GET'
  createWebhook: (params) -> await @_request 'webhooks', params, 'POST'
  getWebhookById: (webhookId) -> await @_request "webhooks/#{webhookId}", {}, 'GET'
  deleteWebhookById: (webhookId) -> await @_request "webhooks/#{webhookId}", {}, 'DELETE'
  updateWebhookById: (webhookId, params) -> await @_request "webhooks/#{webhookId}", params, 'PATCH'

  # Payments
  createPayment: (orderId, params) -> await @_request "orders/#{orderId}/payments", params, 'POST'
  getPaymentById: (orderId, paymentId) -> await @_request "orders/#{orderId}/payments/#{paymentId}", {}, 'GET'
  capturePayment: (orderId, paymentId, params) -> await @_request "orders/#{orderId}/payments/#{paymentId}/capture", params, 'POST'
  cancelPayment: (orderId, paymentId, params) -> await @_request "orders/#{orderId}/payments/#{paymentId}/cancel", params, 'POST'

  # Refund
  createRefund: (orderId, paymentId, params) -> await @_request "orders/#{orderId}/payments/#{paymentId}/refunds", params, 'POST'

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
    # console.log('ioka', response)
    json = await response.json()
    # console.log('ioka::_request', {url, options, json})
    if json?.code is 'Unauthorized'
      throw new Meteor.Error(401, 'errors.unauthorized')
    # text = await response.text()
    # replacer = (key, value) ->
    #   if value instanceof Map
    #     return {
    #       dataType: 'Map',
    #       value: Array.from(value.entries()), # or with spread: value: [...value]
    #     }
    #   else
    #     return value
    # console.log 'IokaClient.request', {response, headers: Array.from(response.headers.entries()), options, json}
    json

  _getRedirectUrl: (response, options) ->
    console.log('ioka::_getRedirectUrl', {response, options})
    config = @config()
    if config.isTest
      checkoutBaseUrl = 'https://stage-checkout.ioka.kz'
    else
      checkoutBaseUrl = 'https://checkout.ioka.kz'
    redirectUrl = "#{checkoutBaseUrl}/orders/#{response.order.id}?orderAccessToken=#{response.order_access_token}"
    if options?.isSaveCard
      redirectUrl = "#{checkoutBaseUrl}/customers/#{response.customer_id}?customerAccessToken=#{response.customer_access_token}"
    redirectUrl

  _sign1: (message, secret) -> crypto.createHmac('sha256', secret).update(message).digest('hex')

  _formatPayload: (json) ->
    payload = JSON.parse(json, (k, v) -> return v)
    # console.log('Ioka::_formatPayload', {payload})
    keys = []
    space = null
    JSON.stringify(payload, (key, value) -> keys.push(key); return value)
    keys.sort()
    JSON.stringify(payload, keys, space)

  _sign: (payload, secret) ->
    data = @_formatPayload(payload)
    # console.log('Ioka::_sign', {data})
    hmac = crypto.createHmac 'sha256', secret
    hmac.update Buffer.from(data, 'utf-8')
    hmac.digest 'hex'

  _updateWebhook: (pathname) ->
    config = @config()
    pathname = "/api/#{config.callbackPathname}" unless pathname
    url = "#{config.siteUrl}#{pathname}"
    list = await @getWebhooks()
    # console.log 'Ioka._updateWebhook list', {list}

    if list?.code is 'Unauthorized'
      console.error 'Ioka._updateWebhook wrong secret key'
      return Promise.resolve()

    if list?.length > 1
      promises = []
      for i in [1..list.length - 1]
        item = list[i]
        promises.push @deleteWebhookById(item.id)
      await Promise.all promises

    if not list or list.length < 1
      response = await @createWebhook {
        url
        events: WEBHOOK_EVENTS
      }
      console.log 'Ioka._updateWebhook create response', response
      @_signatureSecret = response.key
      return
    
    if list?.length > 0
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
        # console.log 'Ioka._updateWebhook update response', {response, url}
      @_signatureSecret = item.key
    return

  _registerHandler: (pathname, updateWebhook = true) ->
    config = @config()
    handlerIndex = WebApp.rawConnectHandlers.stack.findIndex (i) => i.handler is @_handler
    if handlerIndex > 0
      WebApp.rawConnectHandlers.stack.splice handlerIndex, 1
    WebApp.rawConnectHandlers.use pathname, @_handler
    # if config.secretKey and updateWebhook
    #   @_updateWebhook pathname

  # Webhooks handler
  _handler: (req, res, next) =>
    config = @config()
    method = req.method

    response = (code, message) ->
      res.setHeader 'Content-Type', 'application/json'
      res.writeHead code
      res.end message

    console.log 'Ioka.handler method', method, req.headers, req.url

    if method is 'POST'
      chunksLength = 0
      chunks = []

      body = await new Promise (resolve, reject) ->
        req.on 'data', (chunk) ->
          # console.log 'Ioka.handler POST data chunk', chunk
          chunks.push(chunk)
          chunksLength += chunk.length
        req.on 'end', -> resolve Buffer.concat(chunks, chunksLength).toString('utf-8')
        req.on 'error', reject

      unless body
        console.warn 'Ioka.handler: Empty POST body'
        return response 400

      payload = body
      params = JSON.parse(body)
    else
      url = new URL(Meteor.absoluteUrl(req.url))
      payload = Object.fromEntries(url.searchParams)
      unless payload
        console.warn 'Ioka.handler: Empty GET query'
        return response 400
      params = url.searchParams.toString()

    console.log 'Ioka.handler', payload, params

    signatureHeader = req.headers[SIGNATURE_HEADER_NAME]

    unless signatureHeader
      console.warn 'Ioka.handler: Request without signature', {[SIGNATURE_HEADER_NAME]: signatureHeader}
      return response 401

    signature = @_sign payload, @_signatureSecret
    # signature = @_sign payload, config.secretKey

    # TODO: signature generation algo

    # if signature isnt signatureHeader
    #   console.warn 'Ioka.handler: Wrong request signature. Hack possible', {
    #     signatureSecret: @_signatureSecret
    #     signature
    #     [SIGNATURE_HEADER_NAME]: signatureHeader
    #   }
    #   return response 401

    @_onNotification?(params)
    return response 200

export default Ioka = new Ioka

signTest = ->
  config = getConfig()
  webhookSecret = '11cf6a7d5999eac284b117ebb7a443c6da9af8904cf99d5601e9c5287af6874b'
  # _sign = (message, secret) -> crypto.createHmac('sha256', secret).update(message).digest('hex')
  body1 = '{"event": "PAYMENT_CAPTURED", "order": {"id": "ord_QDNUK6JH11", "status": "PAID", "created_at": "2021-11-09T10:05:55.358023", "amount": 1050000, "currency": "KZT", "capture_method": "AUTO", "external_id": "hqH2B2rkqiWJDPH7X", "description": "\u041e\u043f\u043b\u0430\u0442\u0430 \u0431\u0440\u043e\u043d\u0438: eXqu5cXrufMsLeq3S", "extra_info": null, "due_date": null, "back_url": "https://42c9-2a03-32c0-3000-f0c0-81a5-bd88-91e9-381a.ngrok.io/accounts/my-bookings/eXqu5cXrufMsLeq3S", "success_url": null, "failure_url": null, "template": null}, "payment": {"id": "pay_L3INB0YJLE", "order_id": "ord_QDNUK6JH11", "status": "CAPTURED", "created_at": "2021-11-09T10:06:02.598026", "approved_amount": 1050000, "captured_amount": 1050000, "refunded_amount": 0, "processing_fee": 0.0, "payer": {"pan_masked": "555555******5599", "expiry_date": "12/24", "holder": "Holder", "payment_system": null, "emitter": null, "email": null, "phone": null, "customer_id": null, "card_id": null}}}'
  body = """{
    "event": "PAYMENT_CAPTURED",
    "order": {
        "id": "ord_D76ZMGHY1M", "status": "PAID",
        "created_at": "2021-11-09T11:44:57.131585",
        "amount": 1050000, "currency": "KZT",
        "capture_method": "AUTO",
        "external_id": "MjjeuWCfRejSEzvkB",
        "description": "Оплата брони: eXqu5cXrufMsLeq3S",
        "extra_info": null,
        "due_date": null,
        "back_url": "https://42c9-2a03-32c0-3000-f0c0-81a5-bd88-91e9-381a.ngrok.io/accounts/my-bookings/eXqu5cXrufMsLeq3S",
        "success_url": null,
        "failure_url": null,
        "template": null
    },
    "payment": {
        "id": "pay_GZRWOO4OWU",
        "order_id": "ord_D76ZMGHY1M",
        "status": "CAPTURED",
        "created_at": "2021-11-09T11:45:06.279855",
        "approved_amount": 1050000,
        "captured_amount": 1050000,
        "refunded_amount": 0,
        "processing_fee": 0.1,
        "payer": {
            "pan_masked": "555555******5599",
            "expiry_date": "12/24",
            "holder": "Holder",
            "payment_system": null,
            "emitter": null,
            "email": null,
            "phone": null,
            "customer_id": null,
            "card_id": null
        }
    }
  }"""
  # signatureHeader = '65d3668da6a3568b75afeb7a3663e593a160b8f6d2d23a33a400a85d69d7fa44'
  signatureHeader = 'ded0a5bf68b02c5d663729bd8dab932af1ac9426c9347e9a5c42ebea1f7d91e8'
  signatureWithMainSecret = Ioka._sign1(body1, config.secretKey)
  signatureWithWebhookSecret = Ioka._sign1(body1, webhookSecret)
  console.log 'signTest', {
    signatureHeader
    signatureWithMainSecret
    signatureWithWebhookSecret
  }

# signTest()
