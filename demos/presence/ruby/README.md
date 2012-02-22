# Presense server in Ruby using 0mq

## Installation

* clone this repository
* `bundle install`

## Start server

`ruby bin/server`

## Start client

`ruby bin/client <name>`, e.g. `ruby bin/client bulat`

### Using client

When client is connected to server, type `list` on command line to see all
other clients server knows about and their online status
