import sys
import os.path
import mimetypes
import collections
import gevent

from ws4py.server.geventserver import WebSocketServer
from stomp4py.server.websocket import StompHandler
from stomp4py.server.base import Subscription

from gevent_zeromq import zmq

context = zmq.Context()

class NullMQConnection(Subscription):
    def __init__(self, handler, frame):
        super(NullMQConnection, self).__init__(handler, frame)
        self.type = frame.headers.get('type', 'connect')
        self.socket_type = frame.headers.get('socket')
        self.uid = '%s-%s' % (frame.conn_id, self.id)
        self.filter = frame.headers.get('filter', '')
        self.listener = None

StompHandler.subscription_class = NullMQConnection

class ZeroMQBridge(object):
    def __init__(self):
        self.connection_by_uid = {}
        self.connection_by_destination = collections.defaultdict(set)

    def __call__(self, frame, payload):
        if frame is None or frame.command == 'DISCONNECT':
            for connection in payload:
                self.close(connection)
        elif frame.command == 'SUBSCRIBE':
            self.connect(payload)
        elif frame.command == 'UNSUBSCRIBE':
            self.close(payload)
        elif frame.command == 'SEND':
            self.send(frame)
        elif frame.command == 'COMMIT':
            for part in payload:
                self.send(part)

    def connect(self, connection):
        connection.socket = context.socket(
            getattr(zmq, connection.socket_type.upper()))
        connection.socket.connect('%s' % (connection.destination))
        
        self.connection_by_uid[connection.uid] = connection
        self.connection_by_destination[connection.destination].add(connection)
        if connection.socket_type == 'sub':
            connection.socket.setsockopt(zmq.SUBSCRIBE, connection.filter)
        if connection.socket_type in ['sub', 'pull', 'dealer']:
            def listen_for_messages():
                while connection.active:
                    connection.send(connection.socket.recv())
            gevent.spawn(listen_for_messages)
    
    def close(self, connection):
        if connection.listener:
            connection.listener.kill()
        connection.socket.close()
        del self.connection_by_uid[connection.uid]
        self.connection_by_destination[connection.destination].remove(connection)
    
    def send(self, frame):
        type = frame.headers.get('socket')
        if type in ['req', 'rep']:
            reply_to = frame.headers.get('reply-to')
            if type == 'req':
                uid = '%s-%s' % (frame.conn_id, reply_to)
            else:
                uid = reply_to
            conn = self.connection_by_uid[uid]
            conn.socket.send(frame.body)
            if type == 'req':
                def wait_for_reply():
                    conn.send(conn.socket.recv())
                conn.listener = gevent.spawn(wait_for_reply)
        elif type in ['pub', 'push', 'dealer']:
            conns = list(self.connection_by_destination[frame.destination])
            if len(conns):
                conns[0].socket.send(frame.body)

if __name__ == '__main__':
    def websocket_handler(websocket, environ):
        StompHandler(websocket, ZeroMQBridge()).serve()

    server = WebSocketServer(('0.0.0.0', 9000), websocket_handler)
    print "Starting NullMQ-ZeroMQ bridge on 9000"
    server.serve_forever()