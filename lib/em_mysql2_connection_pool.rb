require 'mysql2'
require 'mysql2/em'

class EmMysql2ConnectionPool

  class Query
    def initialize(sql, opts, deferrable)
      @sql, @opts, @deferrable = sql, opts, deferrable
    end

    def sql(connection)
      @sql.respond_to?(:call) ? @sql.call(connection) : @sql
    end

    def execute(connection, &block)
      @busy = true
      @query_text = sql(connection)
      q = connection.query @query_text, @opts
      q.callback{ |result| succeed result, connection.affected_rows, &block }
      q.errback{  |error| fail error, &block }
      return q
    rescue StandardError => error
      fail error, &block
    end

    def succeed(result, affected_rows, &block)
      @deferrable.succeed result, affected_rows
    rescue StandardError => error
      fail error, &block
    ensure
      @busy and block and block.call
      @busy = false
    end

    def fail(error, &block)
      @deferrable.errback &default_errback unless has_errbacks?
      @deferrable.fail error, @query_text
    ensure
      @busy and block and block.call
      @busy = false
    end

    def has_errbacks?
      !@deferrable.errbacks.nil?
    end

    def default_errback
      proc{ |error, sql| puts "#{error.class}: '#{error.message}' with query #{sql} in #{error.backtrace.first}" }
    end

  end

  def initialize(conf)
    @pool_size   = conf[:size] || 10
    @on_error    = conf[:on_error]
    @query_queue = EM::Queue.new
    start_queue conf
  end

  def query_backlog
    @query_queue.size
  end

  def worker
    proc{ |connection|
      @query_queue.pop do |query|
        query.execute(connection){ worker.call connection }
      end
    }
  end

  def start_queue(conf)
    @pool_size.times do
      worker.call Mysql2::EM::Client.new conf
    end
  end

  def on_error(&block)
    @on_error = block
  end

  def query(sql, opts={})
    deferrable = EM::DefaultDeferrableWithErrbacksAccessor.new
    deferrable.callback{ |result,affected_rows| yield result, affected_rows } if block_given?
    deferrable.errback &@on_error if @on_error

    @query_queue.push Query.new(sql, opts, deferrable)
    deferrable
  end
end

module EventMachine
  class DefaultDeferrableWithErrbacksAccessor
    include Deferrable
    attr_accessor :errbacks
  end
end
