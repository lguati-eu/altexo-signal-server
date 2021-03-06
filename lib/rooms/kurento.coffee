kurento = require 'kurento-client'
BaseRoom = require './base.coffee'

module.exports = (kurentoClient) ->
  class KurentoRoom extends BaseRoom

    _pipeline: null
    _composite: null
    _endpoints: null
    _hubPorts: null
    _candidateQueues: null

    getProfile: ->
      Object.assign({ p2p: false }, super())

    create: (user) ->
      this._endpoints = new Map()
      this._hubPorts = new Map()
      this._candidateQueues = new Map()

      this.creator = user

      kurentoClient.create('MediaPipeline')
      .then (pipeline) => this._pipeline = pipeline
      .then => this._pipeline.create('Composite')
      .then (composite) => this._composite = composite
      .then => this._addUser(user)

    destroy: ->
      Promise.all(Array.from(this.members, (user) => this._removeUser(user)))
      .then => this._pipeline.release()
      .then => this.emit('destroy')

    addUser: (user) ->
      this._addUser(user).then =>
        this.emit('user:enter', user)

    _addUser: (user) ->
      this.members.add(user)
      this._createEndpoint(user)
      .then => this._createHubPort(user)

    removeUser: (user) ->
      unless this.members.has(user)
        throw new Error('cannot remove not existing user')
      this._removeUser(user).then =>
        this.emit('user:leave', user)

    _removeUser: (user) ->
      this.members.delete(user)
      this._releaseHubPort(user)
      .then => this._releaseEndpoint(user)

    processIceCandidate: (user, candidate) ->
      candidate = (kurento.getComplexType 'IceCandidate')(candidate)
      webRtcEndpoint = this._endpoints.get(user.id)
      unless webRtcEndpoint
        unless this._candidateQueues.has(user.id)
          this._candidateQueues.set(user.id, [])
        candidateQueue = this._candidateQueues.get(user.id)
        candidateQueue.push(candidate)
      else
        webRtcEndpoint.addIceCandidate(candidate)
      return

    processOffer: (user, offerSdp) ->
      webRtcEndpoint = this._endpoints.get(user.id)
      unless webRtcEndpoint
        throw new Error('no endpoint found')
      webRtcEndpoint.processOffer(offerSdp)
      .then (answerSdp) ->
        webRtcEndpoint.gatherCandidates()
        return answerSdp

    restartPeer: (sender) ->
      this._releaseHubPort(sender)
      .then => this._releaseEndpoint(sender)
      .then => this._createEndpoint(sender)
      .then => this._createHubPort(sender)
      .then -> true

    _createEndpoint: (user) ->
      this._pipeline.create('WebRtcEndpoint')
      .then (webRtcEndpoint) =>
        this._endpoints.set(user.id, webRtcEndpoint)

        candidateQueue = this._candidateQueues.get(user.id)
        if candidateQueue
          while candidateQueue.length
            webRtcEndpoint.addIceCandidate(candidateQueue.shift())
          this._candidateQueues.delete(user.id)

        webRtcEndpoint.on 'OnIceCandidate', (ev) ->
          candidate = (kurento.getComplexType 'IceCandidate')(ev.candidate)
          user.sendCandidate(candidate)

        return

    _createHubPort: (user) ->
      webRtcEndpoint = this._endpoints.get(user.id)
      this._composite.createHubPort()
      .then (hubPort) =>
        this._hubPorts.set(user.id, hubPort)
        webRtcEndpoint.connect(hubPort).then ->
          hubPort.connect(webRtcEndpoint)

    _releaseEndpoint: (user) ->
      webRtcEndpoint = this._endpoints.get(user.id)
      this._endpoints.delete(user.id)
      this._candidateQueues.delete(user.id)
      webRtcEndpoint.release()

    _releaseHubPort: (user) ->
      hubPort = this._hubPorts.get(user.id)
      this._hubPorts.delete(user.id)
      hubPort.release()
