{nullmq} = require('../nullmq.js')
{Stomp} = require('../lib/stomp.js')
Stomp.WebSocket = require('./server.mock.js').ReflectorServerMock

describe "nullmq with reflector", ->    
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
  
describe "nullmq.Socket", ->