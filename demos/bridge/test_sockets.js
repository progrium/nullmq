var ctx = null;
var control = null;

module("ZeroMQ test sockets", {
  setup: function() {
    ctx = new nullmq.Context(TEST.url);
    if (control == null) {
      control = new nullmq.Context(TEST.url).socket(nullmq.REQ);
      control.connect('/control');
    }
    control.send("setup");
  },

  teardown: function() {
    control.send("teardown");
    control.recv(function(rep) { });
    ctx.term();
  }
});

function whenReady(fn) {
  control.recv(function(ready) { 
    if (ready == 'ok') {
      fn();
    } else {
      ok(false, "Remote setup failed");
    }
  });
}

test("publishing", function() {
  whenReady(function() {
    var message = "Foobar";
    var pub = ctx.socket(nullmq.PUB);
    pub.connect('/sub');
    pub.send(message);
    control.send('sub');
    control.recv(function(msg) {
      start();
      equals(msg, message);
    });
    
  });
  stop(TEST.timeout);
});

test("subscribing", function() {
  whenReady(function() {
    var sub = ctx.socket(nullmq.SUB);
    sub.connect('/pub');
    sub.recv(function(actual) {
      start();
      control.send('pub');
      control.recv(function(expected) {
        equals(actual, expected);
      });
    });
  });
  stop(TEST.timeout);
});

test("pushing", function() {
  whenReady(function() {
    var message = "Foobar";
    var push = ctx.socket(nullmq.PUSH);
    push.connect('/pull');
    push.send(message);
    control.send('push');
    control.recv(function(msg) {
      start();
      equals(msg, message);
    });
  });
  stop(TEST.timeout);
});

test("pulling", function() {
  whenReady(function() {
    var pull = ctx.socket(nullmq.PULL);
    pull.connect('/push');
    pull.recv(function(actual) {
      start();
      control.send('push');
      control.recv(function(expected) {
        equals(actual, expected);
      });
    });
  });
  stop(TEST.timeout);
});

test("requesting", function() {
  whenReady(function() {
    var req = ctx.socket(nullmq.REQ);
    req.connect('/rep');
    req.send("Foobar");
    control.send('rep');
    control.recv(function(expected) {
      req.recv(function(actual) {
        start();
        equals(actual, expected);
      });
      
    });
  });
  stop(TEST.timeout);
});

test("replying", function() {
  whenReady(function() {
    var expected = null;
    var rep = ctx.socket(nullmq.REP);
    rep.connect('/req');
    rep.recvall(function(msg) {
      expected = msg + ":Foobar";
      rep.send(expected);
    });
    control.send('req');
    control.recv(function(actual) {
      start();
      equals(actual, expected);    
    });
  });
  stop(TEST.timeout);
});
