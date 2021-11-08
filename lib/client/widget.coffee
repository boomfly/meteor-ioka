scriptUrl = 'https://cdn.ioka.kz/ioka-widget-stage.js'
loaded = false
loading = false
reactComponent = null

loadWidget = ->
  new Promise (resolve, reject) ->
    loading = true
    scriptEl = document.createElement('script')
    scriptEl.src = scriptUrl
    document.body.appendChild(scriptEl)
    scriptEl.addEventListener 'load', ->
      loaded = true
      loading = false
      resolve()
    scriptEl.addEventListener 'error', ->
      loaded = false
      loading = false
      reject()

export showWidget = (params) ->
  if loading
    throw new Error 'errors.loading_please_wait'

  if not loaded
    await loadWidget()

  widget = new IokaWidget params
  console.log widget
  # widget.initPayment()
  widget

export getReactComponent = (options) ->
  if loading
    throw new Error 'errors.loading_please_wait'

  if not loaded
    await loadWidget()

  return reactComponent if reactComponent

  console.log IokaWidget

  {React, ReactDOM} = options
  Component = IokaWidget.driver 'react', {
    React
    ReactDOM
  }