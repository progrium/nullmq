var ctx1 = null;
var ctx2 = null;
var ctx3 = null;

module("Request-Reply", {
  setup: function() {
    ctx1 = new nullmq.Context(TEST.url);
    ctx2 = new nullmq.Context(TEST.url);
    ctx3 = new nullmq.Context(TEST.url);
  },

  teardown: function() {
    ctx1.term();
    ctx2.term();
    ctx3.term();
  }
});

test("basic request-reply", function() {
  var message = "Foobar";
  
  var rep = ctx1.socket(nullmq.REP);
  rep.bind('/echo');
  rep.recvall(function(msg) {
    rep.send(msg);
  });
  
  var req = ctx2.socket(nullmq.REQ);
  req.connect('/echo');
  req.send(message);
  req.recv(function(msg) {
    start();
    equals(msg, message);
  })

  stop(TEST.timeout);
});

test("round robin across connected reply sockets", function() {
  var messages = [];
  
  var rep1 = ctx1.socket(nullmq.REP);
  rep1.bind('/reply1');
  rep1.recvall(function(msg) {
    rep1.send('reply1');
  });
  
  var rep2 = ctx1.socket(nullmq.REP);
  rep2.bind('/reply2');
  rep2.recvall(function(msg) {
    rep2.send('reply2');
  });
  
  var req = ctx2.socket(nullmq.REQ);
  req.connect('/reply1');
  req.connect('/reply2');
  req.send("First request");
  req.recv(function(msg) {
    start();
    messages.push(msg);
    
    req.send("Second request");
    req.recv(function(msg) {
      messages.push(msg);
      
      notEqual(messages.indexOf('reply1'), -1);
      notEqual(messages.indexOf('reply2'), -1);
    });
  })

  stop(TEST.timeout);
});

test("mixing connect and bind reply sockets in different contexts", function() {
  var messages = [];
  
  var rep1 = ctx1.socket(nullmq.REP);
  rep1.bind('/rep');
  rep1.recvall(function(msg) {
    rep1.send('replyA');
  });
  
  var rep2 = ctx2.socket(nullmq.REP);
  rep2.connect('/req');
  rep2.recvall(function(msg) {
    rep2.send('replyB');
  });
  
  var req = ctx3.socket(nullmq.REQ);
  req.connect('/rep');
  req.bind('/req');
  req.send("First request");
  req.recv(function(msg) {
    start();
    messages.push(msg);
    
    req.send("Second request");
    req.recv(function(msg) {
      messages.push(msg);
      
      notEqual(messages.indexOf('replyA'), -1);
      notEqual(messages.indexOf('replyB'), -1);
    });
  })

  stop(TEST.timeout);
});