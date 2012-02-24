require 'thread'
require 'json'

module Presence
  class Server
    def initialize(context, threads=Thread)
      @context  = context
      @threads  = threads
      @changes  = Queue.new
      @messages = Queue.new
      @clients  = {}
    end

    def start
      @threads.abort_on_exception = true
      start_pub
      start_router
      start_pull
      start_message_pull
      start_message_pub
    end

    def stop
      stop_pub
      stop_router
      stop_pull
      stop_message_pull
      stop_message_pub
      @context.terminate
    end

    def run
      loop do
        @clients.dup.each do |name, client|
          if client['online'] && ((Time.now - client['last_seen']) > client['timeout'])
            @clients[name]['online'] = false
            @changes << JSON.generate({
              "name" => name,
              "online" => false
            })
          end
        end
      end
    end

    private

    def start_pub
      @pub = spawn_socket('tcp://*:10001', ZMQ::PUB) do |sock|
        change = @changes.pop
        $stdout << change+"\r\n"
        sock.send_string(change)
      end
    end

    def stop_pub
      @pub[:stop] = true
    end

    def start_router
      @router = spawn_socket('tcp://*:10002', ZMQ::ROUTER) do |sock|
        sock.recv_string(address = '')
        sock.recv_string('') if sock.more_parts?
        sock.recv_string(data = '') if sock.more_parts?
        sock.send_string(address, ZMQ::SNDMORE)
        sock.send_string('', ZMQ::SNDMORE)
        case data
        when "list"
          sock.send_string(JSON.generate(Hash[*(
            @clients.dup.map do |k, v|
              [k, {"name" => k, "online" => v['online'], "text" => v['text']}]
            end.flatten
          )]))
        else
          sock.send_string(JSON.generate({
            "error" => true,
            "reason" => "unknown"
          }))
        end
      end
    end

    def stop_router
      @router[:stop] = true
    end

    def start_pull
      @pull = spawn_socket('tcp://*:10003', ZMQ::PULL) do |sock|
        sock.recv_string(change = '')
        process_change(change)
      end
    end

    def stop_pull
      @pull[:stop] = true
    end

    def spawn_socket(endpoint, socket_type)
      @threads.new(@context.socket(socket_type)) do |sock|
        sock.bind(endpoint)

        thread = @threads.current
        thread[:stop] = false

        until thread[:stop]
          yield sock
        end

        sock.close
      end
    end

    def process_change(change)
      begin
        data = JSON.parse(change)
      rescue JSON::ParserError
        return
      end
      client = @clients[data["name"]] || {}
      client["last_seen"] = Time.now
      if client["online"] != data["online"]
        @changes << JSON.generate({
          "name" => data["name"],
          "online" => data["online"]
        })
        client["online"] = data["online"]
      end
      if client["text"] != data["text"]
        @changes << JSON.generate({
          "name" => data["name"],
          "text" => data["text"]
        })
        client["text"] = data["text"]
      end
      client["timeout"] = data["timeout"]
      @clients[data["name"]] = client unless @clients[data["name"]]
    end

    def start_message_pull
      @message_pull = spawn_socket('tcp://*:10004', ZMQ::PULL) do |sock|
        sock.recv_string(change = '')
        process_message(change)
      end
    end

    def stop_message_pull
      @message_pull[:stop] = true
    end

    def process_message(raw)
      begin
        data = JSON.parse(raw)
      rescue JSON::ParserError
        return
      end

      @messages << JSON.generate({
        "name" => data['name'],
        "text" => data['text'],
        "timestamp" => Time.now
      })
    end

    def start_message_pub
      @message_pub = spawn_socket('tcp://*:10005', ZMQ::PUB) do |sock|
        message = @messages.pop
        sock.send_string(message)
      end
    end

    def stop_message_pub
      @message_pub[:stop] = true
    end
  end
end
