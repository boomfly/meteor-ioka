# Meteor Ioka.kz integration

Прием платежей через платежный шлюз Ioka.kz для Meteor.js.

## Установка

```shell
meteor add boomfly:meteor-ioka
```

## Пример использования

```coffeescript
import React from 'react'
import ReactDOM from 'react-dom'
import Ioka from 'meteor/boomfly:meteor-ioka'

Ioka.config {
  secretKey: ''                   # Секретный ключ из настроек магазина
  siteUrl: 'https://example.com'
  currency: 'KZT'
  isTest: true               # Тестовый режим для отладки подключения
  debug: true
}

if Meteor.isServer
  Meteor.methods {
    placeOrder: (amount) ->
      params =
        pg_amount: amount
      try
        response = Ioka.initPaymentSync params
      catch error
        response = error
      response
  }

if Meteor.isClient
  class PaymentButton extends React.Component
    placeOrder: ->
      Meteor.call 'placeOrder', 100, (error, result) ->
        window.location.href = result.pg_redirect_url._text # Переправляем пользователя на страницу оплаты

    render: ->
      <button className='btn btn-success' onClick={@placeOrder}>Оплатить 100 KZT</button>

  ReactDOM.render <PaymentButton />, document.getElementById('app')
```

## API

### Ioka.createOrder(params)

Инициализация платежа

**params** - Объект, полный список допустимых параметров можно посмотреть на [странице](https://landing.ioka.kz/docs_v2.html#operation/CreateOrder)

**return** - `Promise`

## Events

### Ioka.onNotification(callback)

Обработка результата платежа

**callback** - Функция обработки результата платежа, принимает 1 параметр (params). Полный список параметров на [странице](https://landing.ioka.kz/docs_v2.html#tag/webhooks)

**пример**:

```coffeescript
Ioka.onNotification (params) ->
  order = Order.findOne params.pg_order_id
  if not order
    pg_status: 'rejected'
    pg_description: "Order with _id: '#{params.pg_order_id}' not found"
  else
    if order.status is OrderStatus.PENDING_PAYMENT
      pg_status: 'ok'
    else if order.status is OrderStatus.CANCELLED
      pg_status: 'rejected'
      pg_description: 'Order cancelled'
    else if order.status is OrderStatus.PROCESSED
      pg_status: 'rejected'
      pg_description: 'Order already processed'
```
