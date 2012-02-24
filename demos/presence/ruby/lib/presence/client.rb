require 'thread'
require 'json'

module Presence
  class Client
    def initialize(context, name, text=nil, threads=Thread)
      @context  = context
      @name     = name
      @peers    = {}
      @threads  = threads
      @messages = Queue.new
    end

    def connect
      @threads.abort_on_exception = true
      start_sub
      request_peers
      start_push
      start_message_sub
      start_message_push
    end

    def disconnect
      stop_sub
      stop_push
      stop_message_sub
      stop_message_push
      @context.terminate
    end

    def run
      loop do
        while cmd = $stdin.gets.chomp
          case cmd
          when "list"
            $stdout.puts @peers.inspect
          when "text"
            @text = $stdin.gets.chomp
          when "say"
            @messages << $stdin.gets.chomp
          when "quit"
            break
          end
        end
      end
    end

    private

    def start_sub
      @subscribed = false
      @sub = spawn_socket("tcp://localhost:10001", ZMQ::SUB) do |sock|
        @subscribed = sock.setsockopt(ZMQ::SUBSCRIBE, '') == 0 unless @subscribed
        sock.recv_string(change = '')
        process_change(change)
      end
    end

    def stop_sub
      @sub[:stop] = true
    end

    def start_push
      @push = spawn_socket("tcp://localhost:10003", ZMQ::PUSH) do |sock|
        sock.send_string(JSON.generate({
          "name" => @name,
          "text" => @text,
          "online" => true,
          "timeout" => 2
        }))
        sleep(1)
      end
    end

    def stop_push
      @push[:stop] = true
    end

    def spawn_socket(endpoint, socket_type)
      @threads.new(@context.socket(socket_type)) do |sock|
        thread = @threads.current
        thread[:stop] = false

        sock.connect(endpoint)

        until thread[:stop]
          yield sock
        end

        sock.close
      end
    end

    def process_change(change)
      begin
        client = JSON.parse(change)
      rescue JSON::ParserError
        return
      end
      @peers[client['name']] ||= {}
      @peers[client['name']].merge!(client)
    end

    def request_peers
      request = @context.socket(ZMQ::REQ)
      request.connect("tcp://localhost:10002")

      request.send_string('list')
      request.recv_string(data = '')
      begin
        peers = JSON.parse(data)
      rescue JSON::ParserError
        peers = []
      end

      peers.each do |name, peer|
        @peers[name] = peer
      end

      request.close
    end

    def start_message_sub
      @message_subscribed = false
      @message_sub = spawn_socket("tcp://localhost:10005", ZMQ::SUB) do |sock|
        @message_subscribed = sock.setsockopt(ZMQ::SUBSCRIBE, '') == 0 unless @message_subscribed
        sock.recv_string(message = '')
        process_message(message)
      end
    end

    def stop_message_sub
      @message_sub[:stop] = true
    end

    def process_message(message)
      begin
        data = JSON.parse(message)
      rescue JSON::ParserError
        return
      end
      $stdout << sprintf("[%s] <%s> %s", data['timestamp'], data['name'], data['text'])
      $stdout << "\r\n"
    end

    def start_message_push
      @message_push = spawn_socket("tcp://localhost:10004", ZMQ::PUSH) do |sock|
        message = @messages.pop
        sock.send_string(JSON.generate({
          "name" => @name,
          "text" => message
        }))
      end
    end

    def stop_message_push
      @message_push[:stop] = true
    end
  end
end
