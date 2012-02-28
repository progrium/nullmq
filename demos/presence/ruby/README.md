# Presense and chat server in Ruby using 0mq

## Installation

* clone this repository
* `bundle install`

## Start presence server

`./bin/presence_server`

## Start chat server

`./bin/chat_server`

## Start presence client

`./bin/presence_client <name> <text>`, e.g. `./bin/presence_client bulat "I'm online"`

## Start chat client

`./bin/chat_client <name>`, e.g. `./bin/chat_client bulat`

### Using chat client

When client is connected to server, type any message and hit enter to see it displayed to peers
