require 'mysql2'
require 'mysql2/em'

class EmMysql2ConnectionPool
  
  class Query
    def initialize(sql, opts, deferrable, on_error = nil)
      @sql, @opts, @deferrable, @on_error = sql, opts, deferrable, on_error
    end
    
    def sql(connection)
      @sql.respond_to?(:call) ? @sql.call(connection) : @sql
    end
    
    def execute(connection, &block)
      @busy = true
      query_text = sql(connection)
      q = connection.query query_text, @opts
      q.callback{ |result| succeed result, connection.affected_rows, &block }
      q.errback{  |error|  fail    error, query_text, &block }
      return q
    rescue Exception => e
      do_error(e, query_text)
    end
    
    def succeed(result, affected_rows, &block)
      @deferrable.succeed result, affected_rows
    ensure
      @busy and block.call
      @busy = false
    end
    def fail(error, sql, &block)
      @deferrable.fail error
    ensure
      do_error(error, sql)
      @busy and block.call
      @busy = false
    end
    
    def do_error(e, sql)
      if @on_error.respond_to?(:call)
        @on_error.call(e, sql)
      end
    end
  end
  
  def initialize(conf)
    @pool_size   = conf[:size] || 10
    @query_queue = EM::Queue.new
    @on_error    = conf[:on_error]
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
  
  def query(sql, opts={})
    deferrable = EM::DefaultDeferrable.new
    deferrable.callback{ |result,affected_rows| yield result, affected_rows } if block_given?
    @query_queue.push Query.new(sql, opts, deferrable, @on_error)
    deferrable
  end
end
