{nullmq} = require('../nullmq.js')
{Stomp} = require('../lib/stomp.js')
Stomp.WebSocket = require('./server.mock.js').ReflectorServerMock

describe "nullmq with reflector", ->
  it "round robins and fans-in for PUSH-PULL pipelining", ->
    url = "ws://endpoint"
    received = 0
    messages = []
    sink = null
    message = "Foobar"
    ctx = new nullmq.Context url, ->
      worker1in = ctx.socket(nullmq.PULL)
      worker1out = ctx.socket(nullmq.PUSH)
      worker1in.connect('/source')
      worker1out.connect('/sink')
      worker1in.recvall (msg) -> 
        worker1out.send "worker1: #{msg}"
      
      worker2in = ctx.socket(nullmq.PULL)
      worker2out = ctx.socket(nullmq.PUSH)
      worker2in.connect('/source')
      worker2out.connect('/sink')
      worker2in.recvall (msg) -> 
        worker2out.send "worker2: #{msg}"
      
      sink = ctx.socket(nullmq.PULL)
      sink.bind('/sink')
      sink.recvall (msg) ->
        messages.push msg
      
      source = ctx.socket(nullmq.PUSH)
      source.bind('/source')
      source.send message
      source.send message
      source.send message
      
    waitsFor -> messages.length > 2
    runs ->
      expect(messages).toContain "worker1: #{message}"
      expect(messages).toContain "worker2: #{message}"
      expect(messages.length).toBe 3
      ctx.term()
      
  it "round robin to REP sockets over several destinations from REQ socket", ->
    url = "ws://endpoint"
    received = 0
    messages = []
    req = null
    ctx = new nullmq.Context url, ->
      rep1 = ctx.socket(nullmq.REP)
      rep1.connect('/destination1')
      rep1.recvall (msg) ->
        rep1.send "rep1"
  
      rep2 = ctx.socket(nullmq.REP)
      rep2.bind('/destination2')
      rep2.recvall (msg) ->
        rep2.send "rep2"
  
      req = ctx.socket(nullmq.REQ)
      req.connect('/destination1')
      req.connect('/destination2')
      req.send("foo")
      req.recv (reply) ->
        messages.push reply
        received++
      
    waitsFor -> received > 0
    runs ->
      expect(messages).toContain "rep1"
      req.send("bar")
      req.recv (reply) ->
        messages.push reply
        received++
      
    waitsFor -> received > 1
    runs ->
      expect(messages).toContain "rep2"
      ctx.term()
      
  it "does fanout when using PUB and SUB over several destinations", ->
    url = "ws://endpoint"
    received = 0
    [messages1, messages2, messages3] = [[],[],[]]
    msg = "Hello world"
    ctx = new nullmq.Context url, ->
    
      sub1 = ctx.socket(nullmq.SUB)
      sub1.connect('/destination1')
      sub1.setsockopt(nullmq.SUBSCRIBE, '')
      sub1.recvall (msg) ->
        messages1.push(msg)
        received++
      
      sub2 = ctx.socket(nullmq.SUB)
      sub2.connect('/destination2')
      sub2.setsockopt(nullmq.SUBSCRIBE, '')
      sub2.recvall (msg) ->
        messages2.push(msg)
        received++
      
      sub3 = ctx.socket(nullmq.SUB)
      sub3.connect('/destination1')
      sub3.connect('/destination2')
      sub3.setsockopt(nullmq.SUBSCRIBE, '')
      sub3.recvall (msg) ->
        messages3.push(msg)
        received++
      
      pub = ctx.socket(nullmq.PUB)
      pub.connect('/destination1')
      pub.connect('/destination2')
      pub.send(msg)
    
    waitsFor -> received >= 4
    runs ->
      expect(messages1).toContain msg
      expect(messages2).toContain msg
      expect(messages3).toContain msg
      expect(messages3.length).toEqual 2
      ctx.term()


describe "nullmq namespace", ->
  it "can create a Context", ->
    url = "ws://endpoint"
    ctx = new nullmq.Context url, ->
      expect(ctx.url).toEqual url
      expect(ctx.sockets.length).toEqual 0
      ctx.term()

describe "nullmq.Context", ->
  url = "ws://endpoint"
  
  it "can create a Socket", ->
    ctx = new nullmq.Context url, ->
      socket = ctx.socket(nullmq.REQ)
      expect(socket.type).toEqual nullmq.REQ
      ctx.term()
  
  it "closes sockets on termination", ->
    ctx = new nullmq.Context url, ->
      socket1 = ctx.socket(nullmq.REQ)
      socket2 = ctx.socket(nullmq.REQ)
      expect(socket1.closed).toEqual false
      expect(socket2.closed).toEqual false
      ctx.term()
      expect(socket1.closed).toEqual true
      expect(socket2.closed).toEqual true
  