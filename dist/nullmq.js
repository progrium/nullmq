(function() {
  var Queue, Socket, Stomp, assert, nullmq;
  var __indexOf = Array.prototype.indexOf || function(item) {
    for (var i = 0, l = this.length; i < l; i++) {
      if (this[i] === item) return i;
    }
    return -1;
  }, __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };
  nullmq = {
    PUB: 1,
    SUB: 2,
    REQ: 3,
    REP: 4,
    XREQ: 5,
    XREP: 6,
    PULL: 7,
    PUSH: 8,
    DEALER: 5,
    ROUTER: 6,
    HWM: 100,
    IDENTITY: 101,
    SUBSCRIBE: 102,
    UNSUBSCRIBE: 103
  };
  assert = function(description, condition) {
    if (condition == null) {
      condition = false;
    }
    if (!condition) {
      throw Error("Assertion: " + description);
    }
  };
  Queue = (function() {
    function Queue(maxsize) {
      this.maxsize = maxsize != null ? maxsize : null;
      this.queue = [];
      this.offset = 0;
      this.watches = [];
    }
    Queue.prototype.getLength = function() {
      return this.queue.length - this.offset;
    };
    Queue.prototype.isEmpty = function() {
      return this.queue.length === 0;
    };
    Queue.prototype.isFull = function() {
      if (this.maxsize === null) {
        return false;
      }
      return this.getLength() >= this.maxsize;
    };
    Queue.prototype.put = function(item) {
      var _base;
      if (!this.isFull()) {
        this.queue.push(item);
        if (typeof (_base = this.watches.shift()) === "function") {
          _base();
        }
        return item;
      } else {

      }
    };
    Queue.prototype.get = function() {
      var item;
      if (this.queue.length === 0) {
        return;
      }
      item = this.queue[this.offset];
      if (++this.offset * 2 >= this.queue.length) {
        this.queue = this.queue.slice(this.offset);
        this.offset = 0;
      }
      return item;
    };
    Queue.prototype.peek = function() {
      if (this.queue.length > 0) {
        return this.queue[this.offset];
      } else {
        return;
      }
    };
    Queue.prototype.watch = function(fn) {
      if (this.queue.length === 0) {
        return this.watches.push(fn);
      } else {
        return fn();
      }
    };
    return Queue;
  })();
  nullmq.Context = (function() {
    function Context(url, onconnect) {
      this.url = url;
      this.onconnect = onconnect;
      this.client = Stomp.client(this.url);
      this.client.connect("guest", "guest", this.onconnect);
      this.connections = {};
      this.sockets = [];
    }
    Context.prototype.socket = function(type) {
      return new Socket(this, type);
    };
    Context.prototype.term = function() {
      var dest, id, socket, _i, _len, _ref, _ref2;
      assert("context is already connected", this.client.connected);
      _ref = this.sockets;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        socket = _ref[_i];
        socket.close();
      }
      _ref2 = this.connections;
      for (dest in _ref2) {
        id = _ref2[dest];
        this.client.unsubscribe(id);
        delete this.connections[dest];
      }
      return this.client.disconnect();
    };
    Context.prototype._send = function(destination, message) {
      var part, transaction, _i, _len;
      assert("context is already connected", this.client.connected);
      if (message instanceof Array) {
        transaction = Math.random() + '';
        this.client.begin(transaction);
        for (_i = 0, _len = message.length; _i < _len; _i++) {
          part = message[_i];
          this.client.send(destination, {
            transaction: transaction
          }, part);
        }
        return this.client.commit(transaction);
      } else {
        return this.client.send(destination, {}, message.toString());
      }
    };
    Context.prototype._connect = function(destination) {
      var id;
      assert("context is already connected", this.client.connected);
      if (__indexOf.call(Object.keys(this.connections), destination) >= 0) {
        return this.connections[destination];
      } else {
        id = this.client.subscribe(destination, __bind(function(frame) {
          var socket, sockets, _i, _len, _ref;
          sockets = 0;
          _ref = this.sockets;
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            socket = _ref[_i];
            if (__indexOf.call(Object.keys(socket.connections), destination) >= 0) {
              socket.recv_queue.put(frame.body);
              sockets++;
            }
          }
          if (sockets === 0 && __indexOf.call(Object.keys(this.connections), destination) >= 0) {
            this.client.unsubscribe(this.connections[destination]);
            return delete this.connections[destination];
          }
        }, this));
        this.connections[destination] = id;
        return id;
      }
    };
    return Context;
  })();
  Socket = (function() {
    function Socket(context, type) {
      this.context = context;
      this.type = type;
      this._dispatch_outgoing = __bind(this._dispatch_outgoing, this);
      this.client = this.context.client;
      this.closed = false;
      this.recv_queue = new Queue();
      this.send_queue = new Queue();
      this.identity = null;
      this.linger = -1;
      this.filters = [];
      this.connections = {};
      this.rr_index = 0;
      this.context.sockets.push(this);
      this.send_queue.watch(this._dispatch_outgoing);
    }
    Socket.prototype.connect = function(destination) {
      var id;
      if (__indexOf.call(Object.keys(this.connections), destination) >= 0) {
        return;
      }
      id = this.context._connect(destination);
      return this.connections[destination] = id;
    };
    Socket.prototype.setsockopt = function(option, value) {
      var _ref;
      switch (option) {
        case nullmq.HWM:
          return this.hwm = value;
        case nullmq.IDENTITY:
          return this._identity(value);
        case nullmq.LINGER:
          return this.linger = value;
        case nullmq.SUBSCRIBE:
          if (this.type !== nullmq.SUB) {
            return;
          }
          if (_ref = !value, __indexOf.call(this.filters, _ref) >= 0) {
            this.filters.push(value);
          }
          return value;
        case nullmq.UNSUBSCRIBE:
          if (this.type !== nullmq.SUB) {
            return;
          }
          if (__indexOf.call(this.filters, value) >= 0) {
            this.filters.splice(this.filters.indexOf(value), 1);
          }
          return value;
        default:
          return;
      }
    };
    Socket.prototype.getsockopt = function(option) {
      switch (option) {
        case nullmq.HWM:
          return this.hwm;
        case nullmq.IDENTITY:
          return this.identity;
        case nullmq.LINGER:
          return this.linger;
        default:
          return;
      }
    };
    Socket.prototype.close = function() {
      this.connections = {};
      return this.closed = true;
    };
    Socket.prototype.send = function(message) {
      var _ref;
      if ((_ref = this.type) === nullmq.PULL || _ref === nullmq.SUB) {
        throw Error("Sending is not implemented for this socket type");
      }
      return this.send_queue.put(message);
    };
    Socket.prototype.recv = function(callback) {
      return this.recv_queue.watch(__bind(function() {
        return callback(this.recv_queue.get());
      }, this));
    };
    Socket.prototype.recvall = function(callback) {
      var watcher;
      watcher = __bind(function() {
        callback(this.recv_queue.get());
        return this.recv_queue.watch(watcher);
      }, this);
      return this.recv_queue.watch(watcher);
    };
    Socket.prototype._identity = function(value) {
      return this.identity = value;
    };
    Socket.prototype._deliver_round_robin = function(message) {
      var connection_count, destination;
      destination = Object.keys(this.connections)[this.rr_index];
      this.context._send(destination, message);
      connection_count = Object.keys(this.connections).length;
      return this.rr_index = ++this.rr_index % connection_count;
    };
    Socket.prototype._deliver_fanout = function(message) {
      var destination, _, _ref, _results;
      _ref = this.connections;
      _results = [];
      for (destination in _ref) {
        _ = _ref[destination];
        _results.push(this.context._send(destination, message));
      }
      return _results;
    };
    Socket.prototype._deliver_routed = function(message) {
      var destination;
      destination = message.shift();
      return this.context._send(destination, message);
    };
    Socket.prototype._dispatch_outgoing = function() {
      var message;
      message = this.send_queue.get();
      switch (this.type) {
        case nullmq.REQ:
        case nullmq.DEALER:
        case nullmq.PUSH:
          this._deliver_round_robin(message);
          break;
        case nullmq.PUB:
          this._deliver_fanout(message);
          break;
        case nullmq.ROUTER:
          this._deliver_routed(message);
          break;
        default:
          assert("outgoing dispatching shouldn't happen for this socket type");
      }
      return this.send_queue.watch(this._dispatch_outgoing);
    };
    return Socket;
  })();
  if (typeof window !== "undefined" && window !== null) {
    window.nullmq = nullmq;
    if (!(window.Stomp != null)) {
      console.log("Required Stomp library not loaded.");
    }
  } else {
    exports.nullmq = nullmq;
    exports.Queue = Queue;
    Stomp = require('./lib/stomp.js').Stomp;
  }
}).call(this);
