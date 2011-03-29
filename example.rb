require File.join(File.expand_path(File.dirname(__FILE__)), 'lib/em_mysql2_connection_pool')

conf = {
    :host => "localhost",
    :database => 'lautfm',
    :socket => '/private/var/lib/mysql/mysql.sock',
    # :port => 
    # :password => 
    # :encoding => 
    :reconnect => true,
    :username => "root",
    # :password => ''
}

my_query = "SELECT * FROM track WHERE in_progress != 0 LIMIT 10"

Mysql2::Client.default_query_options.merge! :symbolize_keys => true, :cast_booleans => true

MySQL = EmMysql2ConnectionPool.new conf

EM.run do
  MySQL.query my_query do |results|
    results.each do |result|
      p result
    end
    EM.stop
  end
end


# Inducing some errors:
EM.run do
  EM.add_timer(2){ EM.stop }
  
  100.times do
    begin
      q = MySQL.query('SELECT SLEEP(0.1)'){ |r| puts '.'; raise 'foobar' }
      q.errback{|e| puts "--> #{e.inspect}"}
    end
  end
end

