require 'rspec'
require File.join(File.expand_path(File.dirname(__FILE__)), '../lib/em_mysql2_connection_pool')

# convinience accessors for the spec:
class EmMysql2ConnectionPool
  attr_accessor :pool_size, :query_queue
end

describe EmMysql2ConnectionPool do
  def in_the_reactor_loop
    EM.run do
      yield
      EM.stop
    end
  end
  
  before(:each) do
    @query_stub = stub('query', :callback => :foo, :errback => :bar)
    @connection_stub = stub('connection', :query => @query_stub)
    
    Mysql2::EM::Client.stub! :new => @connection_stub
    
    @connection_pool = EmMysql2ConnectionPool.new :size => 1
  end
  describe "#initialize" do
    describe "ivars" do
      describe "@pool_size" do
        it "should be assigned via the conf argument" do
          cp = EmMysql2ConnectionPool.new :size => 5
          cp.pool_size.should == 5
        end
        it "should default to 10" do
          cp = EmMysql2ConnectionPool.new({})
          cp.pool_size.should == 10
        end
      end
      describe "@on_error" do
        it "should be assigned via the conf argument" do
          cp = EmMysql2ConnectionPool.new :on_error => :some_proc
          cp.instance_variable_get('@on_error').should == :some_proc
        end
      end
      describe "@query_queue" do
        it "should be an EM::Queue" do
          @connection_pool.query_queue.should be_a(EM::Queue)
        end
      end
    end
    it "should start the queue with the configuration" do
      conf = {:foo => :bar}
      @connection_pool.should_receive(:start_queue).with(conf)
      @connection_pool.send :initialize, conf
    end
  end
  describe "#worker" do
    before(:each) do
      @a_deferrable = EM::DefaultDeferrable.new
      @worker = @connection_pool.worker
      @connection_stub = connection = stub('connection')
    end
    it "should pop a query from the queue" do
      in_the_reactor_loop do
        @connection_pool.query 'Some Query'
        @connection_pool.query_queue.should_receive(:pop).at_least(:once)
        @worker.call @connection_stub
      end
    end
    it "should query the connection" do
      in_the_reactor_loop do
        @connection_pool.query 'Some Query'
        @connection_stub.should_receive(:query).with('Some Query', {}).and_return(@a_deferrable)
        @worker.call @connection_stub
      end
    end
    it "work with proc queries" do
      in_the_reactor_loop do
        @connection_pool.query proc{'Some Query'}
        @connection_stub.should_receive(:query).with('Some Query', {}).and_return(@a_deferrable)
        @worker.call @connection_stub
      end
    end
  end
  describe "#start_queue" do
    it "should add @pool_size connections to the pool" do
      @connection_pool.pool_size = 10
      
      Mysql2::EM::Client.should_receive(:new).exactly(10).times
      @connection_pool.start_queue({})
    end
    it "should start querying with each" do
      @connection_pool.pool_size = 10
      Mysql2::EM::Client.stub(:new => :connection)
      worker = proc{}
      @connection_pool.stub(:worker => worker)
      
      worker.should_receive(:call).with(:connection).exactly(10).times
      @connection_pool.start_queue({})
    end
  end
  describe "#query" do
    it "should push the query to the queue" do
      @connection_pool.query_queue.should_receive(:push).with(an_instance_of EmMysql2ConnectionPool::Query)
      @connection_pool.query 'foobar'
    end
    describe "when a block is given" do
      it "adds a callback with the result and the affected rows" do
        res = false
        deferrable = @connection_pool.query('foobar'){|result,affected_rows| res = [result,affected_rows]}
        deferrable.succeed :res, :rows
        res.should == [:res, :rows]
      end
    end
    describe "when a global on_error handler is set" do
      it "adds it as errback" do
        errback = proc{}
        @connection_pool.on_error &errback
        deferrable = @connection_pool.query('foobar')
        deferrable.errbacks.should == [errback]
      end
    end
  end
  describe "#query_backlog" do
    it "return the size of the query queue" do
      @connection_pool.instance_variable_set('@query_queue', [1,2,3,4,5])
      @connection_pool.query_backlog.should == 5
    end
  end
  describe EmMysql2ConnectionPool::Query do
    before(:each) do
      @a_deferrable = EM::DefaultDeferrableWithErrbacksAccessor.new
      @query = EmMysql2ConnectionPool::Query.new :sql, :opts, @a_deferrable
      @connection = stub(:a_connection, :query => @a_deferrable, :affected_rows => 1)
    end
    describe "#initialize" do
      it "assigns the query parts" do
        query = EmMysql2ConnectionPool::Query.new :sql, :opts, :deferrable
        query.instance_variable_get('@sql').should == :sql
        query.instance_variable_get('@opts').should == :opts
        query.instance_variable_get('@deferrable').should == :deferrable
      end
    end
    describe "#sql" do
      describe "without a given proc" do
        it "returns just the sql" do
          @query.sql(:conn).should == :sql
        end
      end
      describe "with a proc given as sql" do
        it "calls the proc" do
          EmMysql2ConnectionPool::Query.new(proc{:proc_sql}, nil, nil).sql(:conn).should == :proc_sql
        end
        it "calls the proc with the connection given" do
          EmMysql2ConnectionPool::Query.new(proc{|c| c}, nil, nil).sql(:conn).should == :conn
        end
      end
    end
    describe "#execute" do
      it "sets @busy" do
        @query.execute @connection
        @query.instance_variable_get('@busy').should be_true
      end
      it "executes the query on the given connection" do
        @connection.should_receive(:query).with(:sql, :opts).and_return(@a_deferrable)
        @query.execute @connection
      end
      it "succeeds on success" do
        @a_deferrable.should_receive(:succeed)
        this_query = @query.execute @connection
        this_query.succeed
      end
      it "fails on error" do
        @a_deferrable.should_receive(:fail)
        this_query = @query.execute(@connection)
        this_query.fail
      end
      # sort of integrationtests for #success and #fail:
      describe "when succeeding" do
        it "calls the callback with the result and the affected rows" do
          res = false
          this_query = @query.execute(@connection){}
          this_query.callback{|result,affected_rows| res = [result,affected_rows]}
          this_query.succeed :res
          res.should == [:res, 1]
        end
        it "ensures a given block is executed" do
          probe = false
          
          this_query = @query.execute(@connection){ probe = true }
          this_query.callback{ raise 'HELL' }
          this_query.succeed rescue nil
          probe.should be_true
        end
      end
      describe "when failing" do
        it "ensures a given block is executed" do
          probe = false
          
          this_query = @query.execute(@connection){ probe = true }
          this_query.errback{ raise 'HELL' }
          this_query.fail rescue nil
          probe.should be_true
        end
      end
    end
    describe "#succeed" do
      it "calls succeed on the deferrable" do
        @a_deferrable.should_receive(:succeed)
        @query.succeed("result", 3)
      end
      describe "when an error occurs" do
        it "calls #fail" do
          @a_deferrable.callback{ raise }
          @query.should_receive(:fail)
          @query.succeed("result", 3)
        end
      end
      describe "when the connection has been busy so far" do
        it "calls the given block " do
          a = 0
          @query.instance_variable_set('@busy', true)
          @query.succeed("result", 3){ a = 1}
          a.should == 1
        end
      end
      describe "when the connection has NOT been busy so far" do
        it "doesn't" do
          a = 0
          @query.instance_variable_set('@busy', false)
          @query.succeed("result", 3){ a = 1}
          a.should == 0
        end
      end
      it "set @busy to false" do
        @query.instance_variable_set('@busy', true)
        @query.succeed("result", 3){}
        @query.instance_variable_get('@busy').should be_false
      end
    end
    describe "#fail" do
      before(:each) do
        @sql_error = StandardError.new('error!!1')
        @sql_error.set_backtrace([])
      end
      describe "when the query doesn't have an errback" do
        it "adds the default errback" do
          @a_deferrable.should_receive(:errback)
          @query.fail(@sql_error, "sql")
        end
      end
      describe "when the query already has an errback" do
        it "adds the default errback" do
          @a_deferrable.errback{}
          @a_deferrable.should_not_receive(:errback)
          @query.fail(@sql_error, "sql")
        end
      end
      describe "when the connection has been busy so far" do
        it "calls the given block " do
          a = 0
          @query.instance_variable_set('@busy', true)
          @query.fail(@sql_error, "sql"){ a = 1}
          a.should == 1
        end
      end
      describe "when the connection has NOT been busy so far" do
        it "doesn't" do
          a = 0
          @query.instance_variable_set('@busy', false)
          @query.fail(@sql_error, "sql"){ a = 1}
          a.should == 0
        end
      end
      it "calls #fail on the deferrable" do
        @a_deferrable.should_receive(:fail)
        @query.fail(@sql_error, "sql")
      end
      it "set @busy to false" do
        @query.instance_variable_set('@busy', true)
        @query.fail(@sql_error, "sql"){}
        @query.instance_variable_get('@busy').should be_false
      end
    end
    describe "#has_errbacks?" do
      
    end
    describe "#default_errback" do
      
    end
    
  end
  
end