require 'thread'

module Clone
  class Server
    def initialize(context, options, threads=Thread)
      @context = context
      @options = options
      @threads = threads
      @pub_queue = Queue.new
    end

    def start
      @threads.abort_on_exception = true
      start_pull
      start_pub
      start_router
    end

    def stop
      stop_pull
      stop_pub
      stop_router
      @context.terminate
    end

    def on_request(&block)
      @router_handler = block
    end

    def on_push(&block)
      @pull_handler = block
    end

    def publish(msg)
      @pub_queue << msg
    end

    private

    def start_pull
      @pull = spawn_socket(@options[:pull], ZMQ::PULL) do |sock|
        sock.recv_string(payload = '')
        @pull_handler.call(payload)
      end
    end

    def stop_pull
      @pull[:stop] = true
      @threads.kill(@pull)
    end

    def start_pub
      @pub = spawn_socket(@options[:publish], ZMQ::PUB) do |sock|
        sock.send_string(@pub_queue.pop)
      end
    end

    def stop_pub
      @pub[:stop] = true
      @threads.kill(@pub)
    end

    def start_router
      @router = spawn_socket(@options[:router], ZMQ::ROUTER) do |sock|
        sock.recv_string(address = '')
        sock.recv_string('') if sock.more_parts?
        sock.recv_string(data = '') if sock.more_parts?
        sock.send_string(address, ZMQ::SNDMORE)
        sock.send_string('', ZMQ::SNDMORE)
        sock.send_string(@router_handler.call(data))
      end
    end

    def stop_router
      @router[:stop] = true
      @threads.kill(@router)
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
  end
end