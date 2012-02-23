MainController.$inject = ['$updateView'];
function MainController($updateView) {
  this.STATUS_CONNECTING    = Client.CONNECTING;
  this.STATUS_CONNECTED     = Client.CONNECTED;
  this.STATUS_DISCONNECTED  = Client.DISCONNECTED;
  this.STATUS_DISCONNECTING = Client.DISCONNECTING;

  this.client = new Client();
  this.client.onChange = $updateView;

  this.connect = function() {
    this.client.connect();
  }.bind(this);
  this.disconnect = function() {
    this.client.disconnect();
  }.bind(this);

  scope = this;
}

Client.CONNECTING = 2;
Client.CONNECTED = 0;
Client.DISCONNECTED = 1;
Client.DISCONNECTING = 3;

function Client() {
  this.name;
  this.status = Client.DISCONNECTED;
  this.peers = {};
  this.onChange = function() {};
};

Client.prototype.connect = function() {
  if (this.status != Client.DISCONNECTED) {
    return;
  }

  this.context = new nullmq.Context('ws://localhost:9000');
  this.status = Client.CONNECTING;

  this.startSub();
  this.requestPeers();
  this.startPush();

  this.status = Client.CONNECTED;
};

Client.prototype.disconnect = function() {
  if (this.status != Client.CONNECTED) {
    return;
  }

  this.status = Client.DISCONNECTING;

  this.stopSub();
  this.clearPeers();
  this.stopPush();
  this.context.term();

  this.status = Client.DISCONNECTED;

  delete this.context;
};

Client.prototype.requestPeers = function() {
  console.log('requesting peer list');

  var req = this.context.socket(nullmq.REQ);
  req.connect('/127.0.0.1:10002');
  req.send('list');
  req.recv(function(json) {
    console.log(json);
    try {
      var peers = JSON.parse(json);
    } catch (e) {
      return;
    }
    Object.keys(peers).forEach(function(name) {
      this.peers[name] = peers[name];
    }.bind(this));

    this.onChange();
  }.bind(this));

  console.log('peer list accuired');
}

Client.prototype.clearPeers = function() {
  console.log('clearing peer list');

  this.peers = {};

  console.log('peer list cleared');
}

Client.prototype.getPeers = function() {
  return Object.keys(this.peers).map(function(key) {
    return this.peers[key];
  }.bind(this));
}

Client.prototype.startSub = function() {
  console.log('starting sub');

  this.sub = this.context.socket(nullmq.SUB);

  this.sub.connect('/127.0.0.1:10001');
  this.sub.setsockopt(nullmq.SUBSCRIBE, '');

  this.sub.recvall(function (change) {
    console.log(change);
    this.processChange(change);
  }.bind(this));

  console.log('sub started');
}

Client.prototype.stopSub = function() {
  console.log('stopping sub');

  (this.sub.close || angular.noop)();

  console.log('sub stopped');
}

Client.prototype.processChange = function(change) {
  try {
    var peer = JSON.parse(change);
  } catch (e) {
    return;
  }
  this.peers[peer['name']] = peer;
  this.onChange();
}

Client.prototype.startPush = function() {
  console.log('starting push');

  this.push = this.context.socket(nullmq.PUSH);
  this.push.connect('/127.0.0.1:10003');

  var repeater = setInterval(function() {
    if (this.status == Client.CONNECTED) {
      this.push.send(JSON.stringify({
          name: this.name
        , online: true
        , timeout: 2
      }));
    } else {
      clearInterval(repeater);
    }
  }.bind(this), 1000);

  console.log('push started');
}

Client.prototype.stopPush = function() {
  console.log('stopping push');

  (this.push.close || angular.noop)();

  console.log('push stopped');
}
