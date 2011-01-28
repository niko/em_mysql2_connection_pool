require 'mysql2'
require 'mysql2/em'

class EmMysql2ConnectionPool
  def initialize(conf)
    @pool_size   = conf[:size] || 10
    @query_queue = EM::Queue.new
    start_queue conf
  end

  def worker
    proc{ |connection|
      @query_queue.pop do |query|
        sql = query[:sql].is_a?(Proc) ? query[:sql].call(connection) : query[:sql]
        
        connection.query(sql, query[:opts]).callback do |result|
          query[:callback].call result if query[:callback]
          worker.call connection
        end
      end
    }
  end

  def start_queue(conf)
    @pool_size.times do
      worker.call Mysql2::EM::Client.new conf
    end
  end

  def query(sql, opts={}, &block)
    @query_queue.push :sql => sql, :opts => opts, :callback => block
  end
end