nullmq =
  PAIR: 1
  PUB: 1
  SUB: 2
  REQ: 3
  REP: 4
  XREQ: 5
  XREP: 6
  PULL: 7
  PUSH: 8
  XPUB: 9
  XSUB: 10
  DEALER: 11
  ROUTER: 12
  
class nullmq.Context
  constructor: (@url, @options) ->
    
  socket: (type) ->
    new nullmq.Socket this, type
  
  term: ->
    

class nullmq.Socket
  constructor: (@context, @type) ->
  
  connect: (destination) ->
  
  bind: (destination) ->
  
  setsockopt: (option, value) ->
  
  getsockopt: ->
  
  close: ->
    
  
  send: (message) ->
    
  
  recv: ->

window.nullmq = nullmq