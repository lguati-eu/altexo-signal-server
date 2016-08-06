EventEmitter = require('events').EventEmitter


RpcError = {
  PARSE_ERROR: -32700
  INVALID_REQUEST: -32600
  METHOD_NOT_FOUND: -32601
  INVALID_PARAMS: -32602
  INTERNAL_ERROR: -32603
}


class JsonRpc extends EventEmitter

  rpc: {}
  rpcNotify: {}

  constructor: ->
    myrpc = {}
    for own name, func of this.rpc
      myrpc[name] = func.bind(this)

    this.rpc = myrpc

    myrpcNotify = {}
    for own name, func of this.rpcNotify
      myrpcNotify[name] = func.bind(this)

    this.rpcNotify = myrpcNotify

    super()

  attach: (ws) ->
    this._ws = ws

    this._ws.addListener 'message', this._handleMessage
    this._ws.addListener 'error', this._handleError
    this._ws.addListener 'close', this._handleClose

    this.onAttach()

  detach: ->
    this._ws.removeListener 'message', this._handleMessage
    this._ws.removeListener 'error', this._handleError
    this._ws.removeListener 'close', this._handleClose

    this._ws = null

    this.onDetach()

  notify: (method, params) ->
    unless params
      this._send { method }
    else
      this._send { method, params }
    return

  request: (method, params) ->
    requestId = Math.floor(Math.random()*1e9)
    unless params
      this._send { id: requestId, method }
    else
      unless 'object' == typeof params
        params = [].concat(params)
      this._send { id: requestId, method, params }
    return new Promise (resolve, reject) =>
      waitResponse = (response) =>
        unless response.id == requestId
          return
        this.removeListener 'rpc:response', waitResponse
        if response.error
          return reject(response.error)
        resolve(response.result)
      this.addListener 'rpc:response', waitResponse

  onError: (error) ->

  onClose: ->

  onAttach: ->

  onDetach: ->

  _handleError: (error) =>
    this.onError(error)

  _handleClose: =>
    this.onClose()

  _handleMessage: (message) =>
    try
      request = JSON.parse(message)
    catch e
      this._send {
        id: null
        error: {
          code: RpcError.PARSE_ERROR
          message: e.toString()
        }
      }
      return

    if request.result or request.error
      # this is actually a response
      unless request.id
        return
      this.emit 'rpc:response', request
      return

    unless request.method
      this._send {
        id: request.id
        error: {
          code: RpcError.INVALID_REQUEST
          message: 'method is not defined'
        }
      }
      return

    unless request.id
      # this is notification
      method = this.rpcNotify[request.method]
      unless 'function' == typeof method
        return
      try
        if Array.isArray(request.params)
          method.apply(null, request.params)
        else if request.params
          method(request.params)
        else
          method()
      catch e
        return
      return

    method = this.rpc[request.method]
    unless 'function' == typeof method
      this._send {
        id: request.id
        error: {
          code: RpcError.METHOD_NOT_FOUND
          message: "method '#{request.method}' is not defined"
        }
      }
      return

    try
      if Array.isArray(request.params)
        result = method.apply(null, request.params)
      else if request.params
        result = method(request.params)
      else
        result = method()
    catch e
      this._send {
        id: request.id
        error: {
          code: RpcError.INTERNAL_ERROR
          message: e.toString()
        }
      }
      return

    Promise.accept(result)
      .then (result) =>
        this._send { id: request.id, result }
      .catch (error) =>
        this._send { id: request.id, error }

    return

  _send: (message) ->
    this._ws.send(JSON.stringify(message))


module.exports = JsonRpc
