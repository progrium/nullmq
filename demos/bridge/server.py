import sys
import os.path
import mimetypes

import gevent.server

from ws4py.server.geventserver import WebSocketServer
from stomp4py.server.websocket import StompHandler

from gevent_zeromq import zmq

from bridge import ZeroMQBridge

context = zmq.Context()

def control_socket(prefix):
    control = context.socket(zmq.REP)
    control.bind('%s/control' % prefix)
    sockets = None
    while True:
        cmd = control.recv()
        if cmd == 'setup':
            if sockets is None:
                sockets = dict(
                    pub=context.socket(zmq.PUB),
                    sub=context.socket(zmq.SUB),
                    req=context.socket(zmq.REQ),
                    rep=context.socket(zmq.REP),
                    push=context.socket(zmq.PUSH),
                    pull=context.socket(zmq.PULL),)
                for key in sockets:
                    sockets[key].bind('%s/%s' % (prefix, key))
                sockets['sub'].setsockopt(zmq.SUBSCRIBE, '')
            control.send("ok")
        elif cmd == 'teardown':
            #for key in sockets:
            #    sockets[key].close()
            control.send("ok")
        elif cmd == 'pub':
            sockets[cmd].send("Foobar")
            control.send("Foobar")
        elif cmd == 'sub':
            msg = sockets[cmd].recv()
            control.send(msg)
        elif cmd == 'req':
            sockets[cmd].send("Foobar")
            reply = sockets[cmd].recv()
            control.send(reply)
        elif cmd == 'rep':
            request = sockets[cmd].recv()
            sockets[cmd].send("Foobar:%s" % request)
            control.send("Foobar:%s" % request)
        elif cmd == 'push':
            sockets[cmd].send("Foobar")
            control.send("Foobar")
        elif cmd == 'pull':
            msg = sockets[cmd].recv()
            control.send(msg)
        else:
            control.send("Unknown command")

if __name__ == '__main__':
    prefix = sys.argv[1] if len(sys.argv) > 1 else 'ipc:///tmp'
    
    #gevent.spawn(control_socket, prefix)
    
    bridge = ZeroMQBridge(prefix)
    
    def websocket_handler(websocket, environ):
        if environ.get('PATH_INFO') == '/bridge':
            StompHandler(websocket, bridge).serve()
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
    print "Starting NullMQ-ZeroMQ bridge on 9000 for prefix %s..." % prefix
    server.serve_forever()