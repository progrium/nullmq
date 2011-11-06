var ctx1 = null;
var ctx2 = null;
var ctx3 = null;

module("Pipelining", {
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

test("basic push-pull", function() {
  var messages = [];
  var message = "Foobar";
  
  var pull = ctx1.socket(nullmq.PULL);
  pull.connect('/endpoint');
  pull.recvall(function(msg) {
    messages.push(msg);
  });
  
  var push = ctx2.socket(nullmq.PUSH);
  push.connect('/endpoint');
  push.send(message);
  push.send(message);
  
  var wait = setInterval(function() {
    if (messages.length > 1) {
      clearInterval(wait);
      start();
      equals(messages.length, 2);
      notEqual(messages.indexOf(message), -1);
    }
  }, 20);

  stop(TEST.timeout);
});