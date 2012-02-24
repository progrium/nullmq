MainController.$inject = ['$updateView'];
function MainController($updateView) {
  this.STATUS_CONNECTING    = Client.CONNECTING;
  this.STATUS_CONNECTED     = Client.CONNECTED;
  this.STATUS_DISCONNECTED  = Client.DISCONNECTED;
  this.STATUS_DISCONNECTING = Client.DISCONNECTING;

  this.peers = {};

  this.getPeers = function() {
    return Object.keys(this.peers).map(function(name) {
      return this.peers[name]
    }.bind(this))
  }.bind(this);

  this.presenceClient = new Client({
      subscribe: "/localhost:10001"
    , request:   "/localhost:10002"
    , push:      "/localhost:10003"
  });
  this.presenceClient.onResponse = function(payload) {
    Object.merge(this.peers, JSON.parse(payload));
    $updateView();
  }.bind(this);
  this.presenceClient.onPublish = function(payload) {
    var peer = JSON.parse(payload);
    this.peers[peer['name']] = this.peers[peer['name']] || {}
    Object.merge(this.peers[peer['name']], peer);
    $updateView();
  }.bind(this);
  var interval;
  this.presenceClient.onConnect = function() {
    interval = setInterval(function() {
      this.presenceClient.push(JSON.stringify({
          name: this.name
        , online: true
        , text: this.text
        , timeout: 2
      }));
    }.bind(this), 1000);
  }.bind(this);
  this.presenceClient.onDisconnect = function() {
    clearInterval(interval);
    this.peers = {};
  }.bind(this);

  this.messages = [];
  this.chatClient = new Client({
      subscribe: "/localhost:10004"
    , request:   "/localhost:10005"
    , push:      "/localhost:10006"
  });
  this.chatClient.onResponse = function(payload) {
    JSON.parse(payload).forEach(function(msg) {
      this.messages.push(msg);
    }.bind(this));
    $updateView();
  }.bind(this);
  this.chatClient.onPublish = function(payload) {
    var msg = JSON.parse(payload);
    this.messages.push(msg);
    $updateView();
  }.bind(this);
  this.chatClient.onDisconnect = function() {
    this.messages = []
  }.bind(this);

  this.sendMessage = function() {
    if (this.message) {
      this.chatClient.push(JSON.stringify({
          name: this.name
        , text: this.message
      }));
      this.message = '';
    }
  }.bind(this)

  this.connect = function() {
    this.presenceClient.connect();
    this.chatClient.connect();
    $updateView();
  }.bind(this);

  this.disconnect = function() {
    this.presenceClient.disconnect();
    this.chatClient.disconnect();
    $updateView();
  }.bind(this);
}

Client.CONNECTING = 2;
Client.CONNECTED = 0;
Client.DISCONNECTED = 1;
Client.DISCONNECTING = 3;

function Client(options) {
  this.status = Client.DISCONNECTED;
  this.options = options;

  this.onResponse = function(payload) {};
  this.onPublish = function(payload) {};
  this.onConnect = function() {};
  this.onDisconnect = function() {};
};

Client.prototype.connect = function() {
  if (this.status != Client.DISCONNECTED) {
    return;
  }

  this.context = new nullmq.Context('ws://localhost:9000');
  this.status = Client.CONNECTING;

  this.startSub();
  this.doRequest();
  this.startPush();

  this.status = Client.CONNECTED;

  this.onConnect();
};

Client.prototype.disconnect = function() {
  if (this.status != Client.CONNECTED) {
    return;
  }

  this.status = Client.DISCONNECTING;

  this.stopSub();
  this.stopPush();
  this.context.term();
  delete this.context;

  this.status = Client.DISCONNECTED;

  this.onDisconnect();
};

Client.prototype.doRequest = function() {
  var req = this.context.socket(nullmq.REQ);
  req.connect(this.options['request']);
  req.send('');
  req.recv(this.onResponse);
}

Client.prototype.startSub = function() {
  this.subSock = this.context.socket(nullmq.SUB);

  this.subSock.connect(this.options['subscribe']);
  this.subSock.setsockopt(nullmq.SUBSCRIBE, '');

  this.subSock.recvall(this.onPublish);
}

Client.prototype.stopSub = function() {
  (this.subSock.close || angular.noop)();
}

Client.prototype.startPush = function() {
  this.pushSock = this.context.socket(nullmq.PUSH);
  this.pushSock.connect(this.options['push']);
}

Client.prototype.stopPush = function() {
  (this.pushSock.close || angular.noop)();
}

Client.prototype.push = function(payload) {
  if (this.status != Client.CONNECTED) {
    return;
  }
  this.pushSock.send(payload);
}

Object.merge = function(destination, source) {
    for (var property in source) {
        if (source.hasOwnProperty(property)) {
            destination[property] = source[property];
        }
    }
    return destination;
};