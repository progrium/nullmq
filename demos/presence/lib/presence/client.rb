require 'thread'
require 'json'

module Presence
  class Client
    def initialize(context, name)
      @context = context
      @name    = name
      @peers   = {}
      Thread.abort_on_exception = true
    end

    def connect
      start_sub
      request_peers
      start_push
    end

    def disconnect
      stop_sub
      stop_push
      @context.terminate
    end

    def run
      loop do
        while cmd = $stdin.gets.chomp
          case cmd
          when "list"
            $stdout.puts @peers.inspect
          when "quit"
            break
          end
        end
      end
    end

    private

    def start_sub
      @sub = Thread.new(@context.socket(ZMQ::SUB)) do |sock|
        thread = Thread.current
        thread[:stop] = false

        sock.connect("tcp://localhost:10001")
        sock.setsockopt(ZMQ::SUBSCRIBE, '')

        until thread[:stop]
          sock.recv_string(change = '')
          process_change(change)
        end

        sock.close
      end
    end

    def stop_sub
      @sub[:stop] = true
    end

    def start_push
      @push = Thread.new(@context.socket(ZMQ::PUSH)) do |sock|
        thread = Thread.current
        thread[:stop] = false

        sock.connect("tcp://localhost:10003")

        until thread[:stop]
          sock.send_string(JSON.generate({
            "name" => @name,
            "online" => true,
            "timeout" => 2
          }))
          sleep(1)
        end

        sock.close
      end
    end

    def stop_push
      @push[:stop] = true
    end

    def process_change(change)
      begin
        client = JSON.parse(change)
      rescue JSON::ParserError
        return
      end
      @peers[client['name']] = client
    end

    def request_peers
      request = @context.socket(ZMQ::REQ)
      request.connect("tcp://localhost:10002")

      request.send_string('list')
      request.recv_string(data = '')
      JSON.parse(data).each do |name, peer|
        @peers[name] = peer
      end

      request.close
    end
  end
end
