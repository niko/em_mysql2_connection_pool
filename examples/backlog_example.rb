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

Mysql2::Client.default_query_options.merge! :symbolize_keys => true, :cast_booleans => true
MySQL = EmMysql2ConnectionPool.new conf

EM.run do
  EM.add_periodic_timer 1 do
    puts `ps -o rss= -p #{Process.pid}`
    puts MySQL.query_backlog
    
    # Increase number of parallel queries beyond what DB is able to handle.
    # It's about 5000 on my MBP.
    # See memory usage increasing.
    3000.times do
      MySQL.query('SELECT RAND() AS r') do
        print '.'
      end
    end
  end
end
