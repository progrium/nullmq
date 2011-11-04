{WebSocketMock} = require('./websocket.mock.js')
{Stomp} = require('../lib/stomp.js')

class exports.ReflectorServerMock extends WebSocketMock
  # WebSocketMock handlers
  
  handle_send: (msg) =>
    @stomp_dispatch(Stomp.unmarshal(msg))
  
  handle_close: =>
    @_shutdown()
  
  handle_open: =>
    @stomp_init()
    @_accept()
  
  # Stomp server implementation.
  # Keep in mind this Stomp server is 
  # meant to simulate a NullMQ reflector
  
  stomp_init: ->
    @transactions = {}
    @subscriptions = {}
    @mailbox = []
    @rr_index = 0
    @router = setInterval =>
      if @readyState isnt 1 then clearInterval @router
      is_corresponding = (subscription, frame) ->
        # Returns true if destination and socket pairings match
        socket_routing =
          pub: 'sub'
          req: 'rep'
          rep: 'req'
          push: 'pull'
        subscription.destination is frame.destination and \
          subscription.socket is socket_routing[frame.headers.socket]
      while frame = @mailbox.shift()
        # Core routing logic of the reflector
        switch frame.headers['socket']
          when 'pub'
            # Fanout
            for id, sub of @subscriptions when is_corresponding sub, frame
              sub.callback(Math.random(), frame.body)
          when 'req'
            # Round robin w/ reply-to
            reps = (sub for id, sub of @subscriptions when is_corresponding sub, frame)
            reply_to = frame.headers['reply-to']
            @rr_index = ++@rr_index % reps.length
            reps[@rr_index].callback(Math.random(), frame.body, {'reply-to': reply_to})
          when 'rep'
            # Reply-to lookup
            reply_to = frame.headers['reply-to']
            @subscriptions[reply_to].callback(Math.random(), frame.body)
          when 'push'
            # Round robin
            pulls = (sub for id, sub of @subscriptions when is_corresponding sub, frame)
            @rr_index = ++@rr_index % pulls.length
            pulls[@rr_index].callback(Math.random(), frame.body)
    , 20
  
  stomp_send: (command, headers, body=null) ->
    @_respond(Stomp.marshal(command, headers, body))
    
  stomp_send_receipt: (frame) ->
    if frame.error?
      @stomp_send("ERROR", {'receipt-id': frame.receipt, 'message': frame.error})
    else
      @stomp_send("RECEIPT", {'receipt-id': frame.receipt})
    
  stomp_send_message: (destination, subscription, message_id, body, headers={}) ->
    headers['destination'] = destination
    headers['message-id'] = message_id
    headers['subscription'] = subscription
    @stomp_send("MESSAGE", headers, body)

  stomp_dispatch: (frame) ->
    handler = "stomp_handle_#{frame.command.toLowerCase()}"
    if this[handler]?
      this[handler](frame)
      if frame.receipt
        @stomp_send_receipt(frame)
    else
      console.log "StompServerMock: Unknown command: #{frame.command}"

  stomp_handle_connect: (frame) ->
    @session_id = Math.random()
    @stomp_send("CONNECTED", {'session': @session_id})
    
  stomp_handle_begin: (frame) ->
    @transactions[frame.transaction] = []
    
  stomp_handle_commit: (frame) ->
    transaction = @transactions[frame.transaction]
    for frame in transaction
      @mailbox.push(frame)
    delete @transactions[frame.transaction]

  stomp_handle_abort: (frame) ->
    delete @transactions[frame.transaction]

  stomp_handle_send: (frame) ->
    if frame.transaction
      @transactions[frame.transaction].push frame
    else
      @mailbox.push frame

  stomp_handle_subscribe: (frame) ->
    sub_id = frame.id or Math.random()
    cb = (id, body, headers={}) => 
      @stomp_send_message(frame.destination, sub_id, id, body, headers)
    @subscriptions[sub_id] = 
      destination: frame.destination
      callback: cb
      type: frame.headers.type
      socket: frame.headers.socket

  stomp_handle_unsubscribe: (frame) ->
    if frame.id in Object.keys(@subscriptions)
      delete @subscriptions[frame.id]
    else
      frame.error = "Subscription does not exist"
        
  stomp_handle_disconnect: (frame) ->
    @_shutdown()
  
  # Test helpers
  
  test_send: (sub_id, message) ->
    msgid = 'msg-' + Math.random()
    @subscriptions[sub_id][1](msgid, message)
  