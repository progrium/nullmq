require 'thread'

module Clone
  class Client
    def initialize(context, options, threads = Thread)
      @context = context
      @options = options
      @threads = threads
    end

    def connect
      @threads.abort_on_exception = true
      start_sub
      do_request
      start_push
    end

    def disconnect
      stop_sub
      stop_push
      @context.terminate
    end

    def on_response(&block)
      @request_handler = block
    end

    def on_publish(&block)
      @subscribe_handler = block
    end

    def push(&block)
      @push_handler = block
    end

    private

    def start_sub
      @subscribed = false
      @sub = spawn_socket(@options[:subscribe], ZMQ::SUB) do |sock|
        @subscribed = sock.setsockopt(ZMQ::SUBSCRIBE, '') == 0 unless @subscribed
        sock.recv_string(change = '')
        @subscribe_handler.call(change)
      end
    end

    def stop_sub
      @sub[:stop] = true
      @threads.kill(@sub)
    end

    def do_request
      request = @context.socket(ZMQ::REQ)
      request.connect(@options[:request])

      request.send_string('')
      request.recv_string(data = '')
      request.close

      @request_handler.call(data)
    end

    def start_push
      @push = spawn_socket(@options[:push], ZMQ::PUSH) do |sock|
        data = @push_handler.call
        sock.send_string(data)
      end
    end
    
    def stop_push
      @push[:stop] = true
      @threads.kill(@push)
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
  end
end