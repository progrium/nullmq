import collections
import uuid
import os.path
import mimetypes

import gevent.server

from ws4py.server.geventserver import WebSocketServer
from stomp4py.server.websocket import StompHandler
from stomp4py.server.base import Subscription

class NullMQConnection(Subscription):
    def __init__(self, handler, frame):
        super(NullMQConnection, self).__init__(handler, frame)
        self.type = frame.headers.get('type', 'connect')
        self.socket = frame.headers.get('socket')
        self.route_id = '%s-%s' % (frame.conn_id, self.id)

StompHandler.subscription_class = NullMQConnection

def socket_pairing(subscription, frame):
    return subscription.socket == {'pub': 'sub', 'req': 'rep', 
        'rep': 'req', 'push': 'pull',}[frame.headers.get('socket')]

class NullMQReflector(object):
    def __init__(self):
        self.rr_index = 0
        self.channels = collections.defaultdict(set)
        self.subscriber_counts = collections.Counter()
    
    def __call__(self, frame, payload):
        print frame
        if frame is None or frame.command == 'DISCONNECT':
            for subscriber in payload:
                self.unsubscribe(subscriber.destination, subscriber)
        elif frame.command == 'SUBSCRIBE':
            self.subscribe(frame.destination, payload)
        elif frame.command == 'UNSUBSCRIBE':
            self.unsubscribe(frame.destination, payload)
        elif frame.command == 'SEND':
            self.route(frame)
        elif frame.command == 'COMMIT':
            for part in payload:
                self.route(part)
    
    def subscribe(self, destination, subscriber):
        self.subscriber_counts[destination] += 1
        self.channels[destination].add(subscriber)
    
    def unsubscribe(self, destination, subscriber):
        self.subscriber_counts[destination] -= 1
        self.channels[destination].remove(subscriber)
        
        # Clean up counts and channels with no subscribers
        self.subscriber_counts += collections.Counter()
        if not self.subscriber_counts[destination]:
            del self.channels[destination]
    
    def route(self, frame):
        # Core routing logic of the reflector
        socket = frame.headers.get('socket')
        if socket == 'pub':
            # Fanout
            for subscriber in self.channels[frame.destination]:
                if socket_pairing(subscriber, frame):
                    subscriber.send(frame.body)
        elif socket == 'req':
            # Round robin w/ reply-to
            reps = [s for s in self.channels[frame.destination] if socket_pairing(s, frame)]
            self.rr_index = (self.rr_index + 1) % len(reps)
            reply_to = '%s-%s' % (frame.conn_id, frame.headers.get('reply-to'))
            reps[self.rr_index].send(frame.body, {'reply-to': reply_to})
        elif socket == 'rep':
            # Reply-to lookup
            reply_to = frame.headers.get('reply-to')
            for subscriber in self.channels[frame.destination]:
                if subscriber.route_id == reply_to:
                    subscriber.send(frame.body)
        elif socket == 'push':
            # Round robin
            reps = [s for s in self.channels[frame.destination] if socket_pairing(s, frame)]
            self.rr_index = (self.rr_index + 1) % len(reps)
            reps[self.rr_index].send(frame.body)

if __name__ == '__main__':
    reflector = NullMQReflector()
    
    def websocket_handler(websocket, environ):
        if environ.get('PATH_INFO') == '/reflector':
            StompHandler(websocket, reflector).serve()
        else:
            websocket.close()
    
    def http_handler(environ, start_response):
        if '/dist' in environ['PATH_INFO'] and environ['PATH_INFO'].split('/')[1] == 'dist':
            filename = '../..%s' % environ['PATH_INFO']
        else:
            filename = environ['PATH_INFO'].split('/')[-1] or 'index.html'
        if os.path.exists(filename):
            start_response('200 OK', [('Content-type', mimetypes.guess_type(filename)[0])])
            return [open(filename).read()]
        else:
            start_response('404 Not found', [('Content-type', 'text/plain')])
            return ["Not found"]
    
    server = WebSocketServer(('127.0.0.1', 9000), websocket_handler, fallback_app=http_handler)
    print "Starting NullMQ reflector on 9000..."
    server.serve_forever()