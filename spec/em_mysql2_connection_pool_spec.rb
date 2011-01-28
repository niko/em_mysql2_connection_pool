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
    @query_stub = stub('query', :callback => :foo)
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
        @connection_pool.query_queue.should_receive(:pop)
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
    it "pass the connection into the proc query" do
      in_the_reactor_loop do
        @connection_pool.query proc{|connection| connection}
        @connection_stub.should_receive(:query).with(@connection_stub, {}).and_return(@a_deferrable)
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
      @connection_pool.query_queue.should_receive(:push).with({:sql=>"foobar", :opts=>{}, :callback=>nil})
      @connection_pool.query 'foobar'
    end
  end
end