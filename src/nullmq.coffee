nullmq =
  # socket types
  #PAIR: 'pair' # Not sold we should support PAIR
  PUB: 'pub'
  SUB: 'sub'
  REQ: 'req'
  REP: 'rep'
  XREQ: 'dealer' # Deprecated in favor of DEALER
  XREP: 'router' # Deprecated in favor of ROUTER
  PULL: 'pull'
  PUSH: 'push'
  DEALER: 'dealer'
  ROUTER: 'router'
  
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
  
  _SENDERS: ['req', 'dealer', 'push', 'pub', 'router', 'rep']

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
  constructor: (@url, onconnect=->) ->
    @active = false
    @client = Stomp.client(@url)
    @client.connect "guest", "guest", =>
      @active = true
      op() while op = @pending_operations.shift()
    @pending_operations = [onconnect]
    @sockets = []
  
  socket: (type) ->
    new Socket this, type
  
  term: ->
    @_when_connected =>
      assert "context is already connected", @client.connected
      for socket in @sockets
        socket.close()
      @client.disconnect()
  
  _send: (socket, destination, message) ->
    @_when_connected =>
      assert "context is already connected", @client.connected
      headers = {'socket': socket.type}
      if socket.type is nullmq.REQ
        headers['reply-to'] = socket.connections[destination]
      if socket.type is nullmq.REP
        headers['reply-to'] = socket.last_recv.reply_to
      if message instanceof Array
        headers['transaction'] = Math.random()+''
        @client.begin transaction
        for part in message
          @client.send destination, headers, part
        @client.commit transaction
      else
        @client.send destination, headers, message.toString()
  
  _subscribe: (type, socket, destination) ->
    @_when_connected =>
      assert "context is already connected", @client.connected
      id = @client.subscribe destination, (frame) =>
        envelope = {'message': frame.body, 'destination': frame.destination}
        if frame.headers['reply-to']?
          envelope['reply_to'] = frame.headers['reply-to']
        socket.recv_queue.put envelope
      , {'socket': socket.type, 'type': type}
      socket.connections[destination] = id
  
  _connect: (socket, destination) -> @_subscribe('connect', socket, destination)
  _bind: (socket, destination) -> @_subscribe('bind', socket, destination)

  _when_connected: (op) ->
    if @client.connected then op() else @pending_operations.push op
    

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
    @last_recv = undefined
    @context.sockets.push this
    if @type in nullmq._SENDERS
      @send_queue.watch @_dispatch_outgoing
  
  connect: (destination) ->
    if destination in Object.keys(@connections) then return
    @context._connect this, destination
  
  bind: (destination) ->
    if destination in Object.keys(@connections) then return
    @context._bind this, destination
  
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
    for destination, id of @connections
      @client.unsubscribe id
    @connections = {}
    @closed = true
  
  send: (message) ->
    if @type in [nullmq.PULL, nullmq.SUB]
      throw Error("Sending is not implemented for this socket type")
    @send_queue.put(message)
  
  recv: (callback) ->
    @recv_queue.watch => 
      callback @_recv()
  
  recvall: (callback) ->
    watcher = =>
      callback @_recv()
      @recv_queue.watch watcher
    @recv_queue.watch watcher
  
  _recv: ->
    envelope = @recv_queue.get()
    @last_recv = envelope
    envelope.message
  
  _identity: (value) ->
    @identity = value
  
  _deliver_round_robin: (message) ->
    destination = Object.keys(@connections)[@rr_index]
    @context._send this, destination, message
    connection_count = Object.keys(@connections).length
    @rr_index = ++@rr_index % connection_count
  
  _deliver_fanout: (message) ->
    for destination, id of @connections
      @context._send this, destination, message
  
  _deliver_routed: (message) ->
    destination = message.shift()
    @context._send this, destination, message
  
  _deliver_back: (message) ->
    @context._send this, @last_recv.destination, message
  
  _dispatch_outgoing: =>
    if @context.active
      message = @send_queue.get()
      switch @type
        when nullmq.REQ, nullmq.DEALER, nullmq.PUSH
          @_deliver_round_robin message
        when nullmq.PUB
          @_deliver_fanout message
        when nullmq.ROUTER
          @_deliver_routed message
        when nullmq.REP
          @_deliver_back message
        else
          assert "outgoing dispatching shouldn't happen for this socket type"
      @send_queue.watch @_dispatch_outgoing
    else
      setTimeout @_dispatch_outgoing, 20

if window?
  # For use in the browser
  window.nullmq = nullmq
  if not window.Stomp?
    console.log "Required Stomp library not loaded."
  else
    Stomp = window.Stomp
else
  # For testing
  exports.nullmq = nullmq
  exports.Queue = Queue
  {Stomp} = require('./lib/stomp.js')