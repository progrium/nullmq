var ctx1 = null;
var ctx2 = null;
var ctx3 = null;

module("Publish-Subscribe", {
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

test("basic publish-subscribe", function() {
  var messages = [];
  var message = "Foobar";
  
  // Subscriber 1 on Context 1
  var sub1 = ctx1.socket(nullmq.SUB);
  sub1.connect('/publisher');
  sub1.recvall(function(msg) {
    messages.push(msg);
  });
  
  // Subscriber 2 on Context 1
  var sub2 = ctx1.socket(nullmq.SUB);
  sub2.connect('/publisher');
  sub2.recvall(function(msg) {
    messages.push(msg);
  });
  
  // Subscriber 3 on Context 2
  var sub3 = ctx2.socket(nullmq.SUB);
  sub3.connect('/publisher');
  sub3.recvall(function(msg) {
    messages.push(msg);
  });
  
  // Publisher on Context 3
  var pub = ctx3.socket(nullmq.PUB);
  pub.bind('/publisher');
  pub.send(message);
  
  var wait = setInterval(function() {
    if (messages.length > 2) {
      clearInterval(wait);
      start();
      equals(messages.length, 3);
      notEqual(messages.indexOf(message), -1);
    }
  }, 20);

  stop(TEST.timeout);
});