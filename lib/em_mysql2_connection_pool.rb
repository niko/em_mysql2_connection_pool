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
      q = connection.query sql(connection), @opts
      q.callback{ |result| succeed result, connection.affected_rows, &block }
      q.errback{  |error|  fail    error, &block }
      return q
    end
    
    def succeed(result, affected_rows, &block)
      @deferrable.succeed result, affected_rows
    ensure
      @busy and block.call
      @busy = false
    end
    def fail(error, &block)
      @deferrable.fail error
    ensure
      @busy and block.call
      @busy = false
    end
    
  end
  
  def initialize(conf)
    @pool_size   = conf[:size] || 10
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
  
  def query(sql, opts={})
    deferrable = EM::DefaultDeferrable.new
    deferrable.callback{ |result,affected_rows| yield result, affected_rows } if block_given?
    @query_queue.push Query.new(sql, opts, deferrable)
    deferrable
  end
end
