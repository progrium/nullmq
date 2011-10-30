nullmq =
  # socket types
  #PAIR: 0 # Not sold we should support PAIR
  PUB: 1
  SUB: 2
  REQ: 3
  REP: 4
  XREQ: 5 # Deprecated in favor of DEALER
  XREP: 6 # Deprecated in favor of ROUTER
  PULL: 7
  PUSH: 8
  DEALER: 5
  ROUTER: 6
  
  # socket options
  HWM: 100
  IDENTITY: 101
  SUBSCRIBE: 102
  UNSUBSCRIBE: 103
  #LINGER: 104
  #RECONNECT_IVL_MAX: 105
  #RECONNECT_IVL: 106
  #RCVMORE: 107
  #SNDMORE: 108

assert = (description, condition=false) ->
  # We assert assumed state so we can more easily catch bugs.
  # Do not assert if we *know* the user can get to it.
  throw Error "Assertion: #{description}" if not condition

class Queue
  # Originally based on the implementation here:
  # http://code.stephenmorley.org/javascript/queues/
  
  constructor: (@maxsize=null) ->
    @queue = []
    @offset = 0
    @watches = []
  
  getLength: ->
    @queue.length - @offset
  
  isEmpty: ->
    @queue.length is 0
  
  isFull: ->
    if @maxsize is null then return false
    return @getLength() >= @maxsize
  
  put: (item) ->
    if not @isFull()
      @queue.push item
      @watches.shift()?()
      return item
    else
      return undefined
  
  get: ->
    if @queue.length is 0 then return undefined
    item = @queue[@offset]
    if ++@offset*2 >= @queue.length
      @queue = @queue.slice(@offset)
      @offset = 0
    item
  
  peek: ->
    if @queue.length > 0 then @queue[@offset] else undefined
  
  watch: (fn) ->
    if @queue.length is 0
      @watches.push(fn)
    else
      fn()

class nullmq.Context
  constructor: (@url, @onconnect) ->
    @client = Stomp.client(@url)
    @client.connect "guest", "guest", @onconnect
    @connections = {}
    @sockets = []
    
  socket: (type) ->
    new Socket this, type
  
  term: ->
    assert "context is already connected", @client.connected
    for socket in @sockets
      socket.close()
    for dest, id of @connections
      @client.unsubscribe id
      delete @connections[dest]
    @client.disconnect()
  
  _send: (destination, message) ->
    assert "context is already connected", @client.connected
    if message instanceof Array
      transaction = Math.random()+''
      @client.begin transaction
      for part in message
        @client.send destination, {transaction}, part
      @client.commit transaction
    else
      @client.send destination, {}, message.toString()
  
  _connect: (destination) ->
    assert "context is already connected", @client.connected
    if destination in Object.keys(@connections)
      return @connections[destination]
    else
      id = @client.subscribe destination, (frame) =>
        sockets = 0
        for socket in @sockets when destination in Object.keys(socket.connections)
          socket.recv_queue.put frame.body
          sockets++
        if sockets is 0 and destination in Object.keys(@connections)
          @client.unsubscribe @connections[destination]
          delete @connections[destination]
      @connections[destination] = id
      return id
    

class Socket
  constructor: (@context, @type) ->
    @client = @context.client
    @closed = false
    @recv_queue = new Queue()
    @send_queue = new Queue()
    @identity = null
    @linger = -1
    @filters = []
    @connections = {}
    @rr_index = 0
    @context.sockets.push this
    @send_queue.watch @_dispatch_outgoing
  
  connect: (destination) ->
    if destination in Object.keys(@connections) then return
    id = @context._connect destination
    @connections[destination] = id
  
  #bind: (destination) ->
  
  setsockopt: (option, value) ->
    switch option
      when nullmq.HWM then @hwm = value
      when nullmq.IDENTITY then @_identity value
      when nullmq.LINGER then @linger = value
      when nullmq.SUBSCRIBE
        if @type isnt nullmq.SUB then return undefined
        if not value in @filters
          @filters.push value
        value
      when nullmq.UNSUBSCRIBE
        if @type isnt nullmq.SUB then return undefined
        if value in @filters
          @filters.splice @filters.indexOf(value), 1
        value
      else undefined
  
  getsockopt: (option) ->
    switch option
      when nullmq.HWM then @hwm
      when nullmq.IDENTITY then @identity
      when nullmq.LINGER then @linger
      else undefined
  
  close: ->
    @connections = {}
    @closed = true
  
  send: (message) ->
    if @type in [nullmq.PULL, nullmq.SUB]
      throw Error("Sending is not implemented for this socket type")
    @send_queue.put(message)
  
  recv: (callback) ->
    @recv_queue.watch => 
      callback @recv_queue.get()
  
  recvall: (callback) ->
    watcher = =>
      callback @recv_queue.get()
      @recv_queue.watch watcher
    @recv_queue.watch watcher
  
  _identity: (value) ->
    @identity = value
    # TODO: make queues durable
  
  _deliver_round_robin: (message) ->
    destination = Object.keys(@connections)[@rr_index]
    @context._send destination, message
    connection_count = Object.keys(@connections).length
    @rr_index = ++@rr_index % connection_count
  
  _deliver_fanout: (message) ->
    for destination, _ of @connections
      @context._send destination, message
  
  _deliver_routed: (message) ->
    destination = message.shift()
    @context._send destination, message
  
  _dispatch_outgoing: =>
    message = @send_queue.get()
    switch @type
      when nullmq.REQ, nullmq.DEALER, nullmq.PUSH
        @_deliver_round_robin message
      when nullmq.PUB
        @_deliver_fanout message
      when nullmq.ROUTER
        @_deliver_routed message
      else
        assert "outgoing dispatching shouldn't happen for this socket type"
    @send_queue.watch @_dispatch_outgoing

if window?
  # For use in the browser
  window.nullmq = nullmq
  if not window.Stomp?
    console.log "Required Stomp library not loaded."
else
  # For testing
  exports.nullmq = nullmq
  exports.Queue = Queue
  {Stomp} = require('./lib/stomp.js')