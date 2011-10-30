{Queue} = require('../nullmq.js')

describe "Queue", ->
  it "gives you FIFO queue behavior", ->
    q = new Queue()
    item1 = "foobar"
    item2 = ["foobar"]
    item3 = {foo: "bar"}
    item4 = 42
    q.put(item1)
    q.put(item2)
    q.put(item3)
    q.put(item4)
    expect(q.get()).toBe item1
    expect(q.get()).toBe item2
    expect(q.get()).toBe item3
    expect(q.get()).toBe item4
  
  it "can have a maximum size", ->
    q = new Queue(3)
    items = ["foo", "bar", "baz", "qux"]
    expect(q.isFull()).toBeFalsy()
    expect(q.put(items[0])).toBe items[0]
    q.put(items[1])
    q.put(items[2])
    expect(q.isFull()).toBeTruthy()
    expect(q.put(items[3])).toBeUndefined()
    expect(q.getLength()).toEqual 3
  
  it "lets you peek without dequeuing", ->
    q = new Queue()
    q.put("foo")
    q.put("bar")
    q.put("baz")
    q.get() # Drop "foo"
    expect(q.peek()).toEqual "bar"
    expect(q.get()).toEqual "bar"
  
  it "lets you register a one-time watch callback for items", ->
    q = new Queue()
    from_watch = []
    watcher = ->
      from_watch.push q.get()
    q.watch watcher
    q.put("item1")
    q.put("item2")
    expect(q.getLength()).toEqual 1
    expect(from_watch.length).toEqual 1
    expect(from_watch).toContain "item1"
    q.watch watcher
    expect(from_watch.length).toEqual 2
    expect(from_watch).toContain "item2"