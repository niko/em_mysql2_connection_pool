require File.join(File.expand_path(File.dirname(__FILE__)), '../lib/em_mysql2_connection_pool')

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

MySQL = EmMysql2ConnectionPool.new conf

# When no errback is given, EmMysql2ConnectionPool puts the errors:
EM.run do
  EM.add_timer(1){ EM.stop }
  
  10.times do
    q = MySQL.query('SELECT RAND()')
    q.callback{ |r| puts '1'; raise 'foobar' }
  end
end

# When a errback is given, the internal default puts is not used:
EM.run do
  EM.add_timer(1){ EM.stop }
  
  10.times do
    q = MySQL.query('SELECT RAND()')
    q.callback{ |r| puts '2'; raise 'foobaz' }
    q.errback{|e| puts "--> #{e.inspect}"}
  end
end

# When you define an on_error handler on the connection, this will always be used:
MySQL.on_error{ |error, sql| puts "Generic error handler for all queries: #{error} (#{sql})" }
# on_error can also be a proc in the configuration hash.

EM.run do
  EM.add_timer(1){ EM.stop }
  
  10.times do
    q = MySQL.query('SELECT RAND()')
    q.callback{ |r| puts '3'; raise 'foobaz' }
  end
end
