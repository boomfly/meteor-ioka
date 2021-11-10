import {showWidget, getReactComponent} from './widget.coffee'
import {getConfig} from './config'

class Ioka
  config: (cfg) ->
    config = getConfig()
    return config unless cfg
    Object.assign(config, cfg)
  
  widget: (params) ->
    {}

export default Ioka = new Ioka