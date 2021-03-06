require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

GOOD_OPTIONS = [
  [ :reload,   false     ],
  [ :reload,   true      ],
  [ :offset,   0         ],
  [ :offset,   1         ],
  [ :limit,    1         ],
  [ :limit,    2         ],
  [ :order,    [ DataMapper::Query::Direction.new(Article.properties[:created_at], :desc) ] ],
  [ :fields,   Article.properties(:default).defaults.to_a ], # TODO: fill in allowed default value
  #[ :links,    [ :stub ] ], # TODO: fill in allowed default value
  [ :includes, [ :stub ] ], # TODO: fill in allowed default value
]

BAD_OPTIONS = {
  :reload     => 'true',
  :offset     => -1,
  :limit      => 0,
  :order      => [],
  :fields     => [],
  :links      => [],
  :includes   => [],
  :conditions => [],
}

# flatten GOOD_OPTIONS into a Hash to remove default values, since
# default value, when defined, is always listed first in GOOD_OPTIONS
UPDATED_OPTIONS = GOOD_OPTIONS.inject({}) do |options,(attribute,value)|
  options.update attribute => value
end

UPDATED_OPTIONS.merge!({ :fields => [ :id, :author ]})

describe DataMapper::Query do

  describe '.new' do
    describe 'should set the attribute' do
      it '#model with model' do
        query = DataMapper::Query.new(repository(:mock), Article)
        query.model.should == Article
      end

      GOOD_OPTIONS.each do |(attribute,value)|
        it "##{attribute} with options[:#{attribute}] if it is #{value.inspect}" do
          query = DataMapper::Query.new(repository(:mock), Article, attribute => value)
          query.send(attribute).should == value
        end
      end

      describe ' #conditions with options[:conditions]' do
        it 'when they have a one element Array' do
          query = DataMapper::Query.new(repository(:mock), Article, :conditions => [ 'name = "dkubb"' ])
          query.conditions.should == [ [ :raw, 'name = "dkubb"' ] ]
          query.parameters.should == []
        end

        it 'when they have a two or more element Array' do
          bind_values = %w[ dkubb ]
          query = DataMapper::Query.new(repository(:mock), Article, :conditions => [ 'name = ?', *bind_values ])
          query.conditions.should == [ [ :raw, 'name = ?', bind_values ] ]
          query.parameters.should == bind_values

          bind_values = [ 'dkubb', 32 ]
          query = DataMapper::Query.new(repository(:mock), Article, :conditions => [ 'name = ? OR age = ?', *bind_values ])
          query.conditions.should == [ [ :raw, 'name = ? OR age = ?', bind_values ] ]
          query.parameters.should == bind_values

          bind_values = [ %w[ dkubb ssmoot ] ]
          query = DataMapper::Query.new(repository(:mock), Article, :conditions => [ 'name IN ?', *bind_values ])
          query.conditions.should == [ [ :raw, 'name IN ?', bind_values ] ]
          query.parameters.should == bind_values
        end

        it 'when they have another DM:Query as the value of sub-select' do
          class Acl
            include DataMapper::Resource
            property :id, Integer
            property :resource_id, Integer
          end

          acl_query = DataMapper::Query.new(repository(:mock), Acl, :fields=>[:resource_id]) #this would normally have conditions
          query = DataMapper::Query.new(repository(:mock), Article, :id.in => acl_query)
          query.conditions.each do |operator, property, value|
            operator.should == :in
            property.name.should == :id
            value.should == acl_query
          end
        end
      end

      describe ' #conditions with unknown options' do
        it 'when a Symbol object is a key' do
          query = DataMapper::Query.new(repository(:mock), Article, :author => 'dkubb')
          query.conditions.should == [ [ :eql, Article.properties[:author], 'dkubb' ] ]
        end

        it 'when a Symbol::Operator object is a key' do
          query = DataMapper::Query.new(repository(:mock), Article, :author.like => /\Ad(?:an\.)kubb\z/)
          query.conditions.should == [ [ :like, Article.properties[:author], /\Ad(?:an\.)kubb\z/ ] ]
        end
      end
    end

    describe 'should raise a TypeError' do
      it 'when repository is nil' do
        lambda {
          DataMapper::Query.new(nil, NormalClass)
        }.should raise_error(TypeError)
      end

      it 'when model is nil' do
        lambda {
          DataMapper::Query.new(repository(:mock), nil)
        }.should raise_error(ArgumentError)
      end
    end

    describe 'should raise an ArgumentError' do
      it 'when model is a Class that does not include DataMapper::Resource' do
        lambda {
          DataMapper::Query.new(repository(:mock), NormalClass)
        }.should raise_error(ArgumentError)
      end

      it 'when options is not a Hash' do
        lambda {
          DataMapper::Query.new(repository(:mock), Article, nil)
        }.should raise_error(ArgumentError)
      end

      BAD_OPTIONS.each do |attribute,value|
        it "when options[:#{attribute}] is nil" do
          lambda {
            DataMapper::Query.new(repository(:mock), Article, attribute => nil)
          }.should raise_error(ArgumentError)
        end

        it "when options[:#{attribute}] is #{value.kind_of?(Array) && value.empty? ? 'an empty Array' : value.inspect}" do
          lambda {
            DataMapper::Query.new(repository(:mock), Article, attribute => value)
          }.should raise_error(ArgumentError)
        end
      end

      it 'when unknown options use something that is not a Symbol::Operator, Symbol or String is a key' do
        lambda {
          DataMapper::Query.new(repository(:mock), Article, nil => nil)
        }.should raise_error(ArgumentError)
      end
    end

    describe 'should normalize' do
      it '#fields' do
        DataMapper::Query.new(repository(:mock), Article, :fields => [:id]).fields.should == Article.properties(:default).slice(:id).to_a
      end
    end

    describe 'should translate custom types' do
      before(:each) do
        class Acl
          include DataMapper::Resource
          property :id, Integer
          property :is_custom_type, DM::Boolean
        end
      end
      it "should call Boolean#dump for :is_custom_type options" do
        DM::Boolean.should_receive(:dump).with(:false, Acl.properties[:is_custom_type])
        DataMapper::Query.new(repository(:mock), Acl, :is_custom_type => :false)
      end
    end
  end

  describe '#update' do
    before do
      @repository = repository(:mock)
      @query = DataMapper::Query.new(@repository, Article, UPDATED_OPTIONS)
    end

    it 'should instantiate a DataMapper::Query object from other when it is a Hash' do
      other = { :reload => :true }

      mock_query_class = mock('DataMapper::Query class')
      @query.should_receive(:class).with(no_args).ordered.and_return(mock_query_class)
      mock_query_class.should_receive(:new).with(@repository, @query.model, other).ordered.and_return(@query)

      @query.update(other)
    end

    it 'should return self' do
      other = DataMapper::Query.new(repository(:mock), Article)
      @query.update(other).should == @query
    end

    describe 'should overwrite the attribute' do
      it '#model with other model' do
        other = DataMapper::Query.new(repository(:mock), Comment)
        @query.update(other).model.should == Comment
      end

      it '#reload with other reload' do
        other = DataMapper::Query.new(repository(:mock), Article, :reload => true)
        @query.update(other).reload.should == true
      end

      it '#offset with other offset when it is not equal to 0' do
        other = DataMapper::Query.new(repository(:mock), Article, :offset => 1)
        @query.update(other).offset.should == 1
      end

      it '#limit with other limit when it is not nil' do
        other = DataMapper::Query.new(repository(:mock), Article, :limit => 1)
        @query.update(other).limit.should == 1
      end

      [ :eql, :like ].each do |operator|
        it "#conditions with other conditions when updating the '#{operator}' clause to a different value than in self" do
          # set the initial conditions
          @query.update(:author.send(operator) => 'ssmoot')

          # update the conditions, and overwrite with the new value
          other = DataMapper::Query.new(repository(:mock), Article, :author.send(operator) => 'dkubb')
          @query.update(other).conditions.should == [ [ operator, Article.properties[:author], 'dkubb' ] ]
        end
      end

      [ :gt, :gte ].each do |operator|
        it "#conditions with other conditions when updating the '#{operator}' clause to a value less than in self" do
          # set the initial conditions
          @query.update(:created_at.send(operator) => Time.at(1))

          # update the conditions, and overwrite with the new value is less
          other = DataMapper::Query.new(repository(:mock), Article, :created_at.send(operator) => Time.at(0))
          @query.update(other).conditions.should == [ [ operator, Article.properties[:created_at], Time.at(0) ] ]
        end
      end

      [ :lt, :lte ].each do |operator|
        it "#conditions with other conditions when updating the '#{operator}' clause to a value greater than in self" do
          # set the initial conditions
          @query.update(:created_at.send(operator) => Time.at(0))

          # update the conditions, and overwrite with the new value is more
          other = DataMapper::Query.new(repository(:mock), Article, :created_at.send(operator) => Time.at(1))
          @query.update(other).conditions.should == [ [ operator, Article.properties[:created_at], Time.at(1) ] ]
        end
      end
    end

    describe 'should append the attribute' do
      it "#order with other order unique values" do
        order = [
          DataMapper::Query::Direction.new(Article.properties[:created_at], :desc),
          DataMapper::Query::Direction.new(Article.properties[:author],     :desc),
          DataMapper::Query::Direction.new(Article.properties[:title],      :desc),
        ]

        other = DataMapper::Query.new(repository(:mock), Article, :order => order)
        @query.update(other).order.should == order
      end

      it "#order with a property that uses :field => something" do
        class Article
          property :plank, String, :field => 'real_plank'
        end

        query = DataMapper::Query.new(repository(:mock), Article, :order => [:plank.desc])

        order = query.order
        order.size.should == 1
        order.first.property.should == Article.properties[:plank]
        order.first.property.field.should == 'real_plank'
        order.first.direction.should == :desc

        repository = repository(:mock)
        adapter    = repository.adapter
        collection = adapter.read_set(repository, query)

        reader     = mock('reader', :next! => false, :close => nil)
        command    = mock('command', :set_types => nil, :execute_reader => reader)
        connection = mock('connect')
        statement  = 'SELECT "id", "blog_id", "created_at", "author", "title", "real_plank" FROM "articles" ORDER BY "real_plank" DESC'

        adapter.should_receive(:with_connection).and_yield(connection)
        connection.should_receive(:create_command).with(statement).and_return(command)

        # use the kicker method to execute the query
        collection.entries
      end

      # dkubb: I am not sure i understand the intent here. link now needs to be
      #       a DM::Assoc::Relationship or the name (Symbol or String) of an
      #       association on the Resource -- thx guyvdb
      #
      # NOTE: I have commented out :links in the GOOD_OPTIONS above
      #
      [ :links, :includes ].each do |attribute|
        it "##{attribute} with other #{attribute} unique values" do
          pending 'DataMapper::Query::Path not ready'
          other = DataMapper::Query.new(repository(:mock), Article, attribute => [ :stub, :other, :new ])
          @query.update(other).send(attribute).should == [ :stub, :other, :new ]
        end
      end

      it "#fields with other fields unique values" do
        other = DataMapper::Query.new(repository(:mock), Article, :fields => [ :blog_id ])
        @query.update(other).fields.should == Article.properties(:default).slice(:id, :author, :blog_id).to_a
      end

      it '#conditions with other conditions when they are unique' do
        # set the initial conditions
        @query.update(:title => 'On DataMapper')

        # update the conditions, but merge the conditions together
        other = DataMapper::Query.new(repository(:mock), Article, :author => 'dkubb')
        @query.update(other).conditions.should == [ [ :eql, Article.properties[:title], 'On DataMapper' ], [ :eql, Article.properties[:author], 'dkubb' ] ]
      end

      [ :not, :in ].each do |operator|
        it "#conditions with other conditions when updating the '#{operator}' clause" do
          # set the initial conditions
          @query.update(:created_at.send(operator) => [ Time.at(0) ])

          # update the conditions, and overwrite with the new value is more
          other = DataMapper::Query.new(repository(:mock), Article, :created_at.send(operator) => [ Time.at(1) ])
          @query.update(other).conditions.should == [ [ operator, Article.properties[:created_at], [ Time.at(0), Time.at(1) ] ] ]
        end
      end

      it '#conditions with other conditions when they have a one element condition' do
        # set the initial conditions
        @query.update(:title => 'On DataMapper')

        # update the conditions, but merge the conditions together
        other = DataMapper::Query.new(repository(:mock), Article, :conditions => [ 'author = "dkubb"' ])
        @query.update(other).conditions.should == [ [ :eql, Article.properties[:title], 'On DataMapper' ], [ :raw, 'author = "dkubb"' ] ]
      end

      it '#conditions with other conditions when they have a two or more element condition' do
        # set the initial conditions
        @query.update(:title => 'On DataMapper')

        # update the conditions, but merge the conditions together
        other = DataMapper::Query.new(repository(:mock), Article, :conditions => [ 'author = ?', 'dkubb' ])
        @query.update(other).conditions.should == [ [ :eql, Article.properties[:title], 'On DataMapper' ], [ :raw, 'author = ?', [ 'dkubb' ] ] ]
      end
    end

    describe 'should not update the attribute' do
      it '#offset when other offset is equal to 0' do
        other = DataMapper::Query.new(repository(:mock), Article, :offset => 0)
        other.offset.should == 0
        @query.update(other).offset.should == 1
      end

      it '#limit when other limit is nil' do
        other = DataMapper::Query.new(repository(:mock), Article)
        other.limit.should be_nil
        @query.update(other).offset.should == 1
      end

      [ :gt, :gte ].each do |operator|
        it "#conditions with other conditions when they have a '#{operator}' clause with a value greater than in self" do
          # set the initial conditions
          @query.update(:created_at.send(operator) => Time.at(0))

          # do not overwrite with the new value if it is more
          other = DataMapper::Query.new(repository(:mock), Article, :created_at.send(operator) => Time.at(1))
          @query.update(other).conditions.should == [ [ operator, Article.properties[:created_at], Time.at(0) ] ]
        end
      end

      [ :lt, :lte ].each do |operator|
        it "#conditions with other conditions when they have a '#{operator}' clause with a value less than in self" do
          # set the initial conditions
          @query.update(:created_at.send(operator) => Time.at(1))

          # do not overwrite with the new value if it is less
          other = DataMapper::Query.new(repository(:mock), Article, :created_at.send(operator) => Time.at(0))
          @query.update(other).conditions.should == [ [ operator, Article.properties[:created_at], Time.at(1) ] ]
        end
      end
    end
  end

  describe '#merge' do
    before do
      @query = DataMapper::Query.new(repository(:mock), Article)
    end

    it 'should pass arguments as-is to duplicate object\'s #update method' do
      dupe_query = @query.dup
      @query.should_receive(:dup).with(no_args).ordered.and_return(dupe_query)
      dupe_query.should_receive(:update).with(:author => 'dkubb').ordered
      @query.merge(:author => 'dkubb')
    end

    it 'should return the duplicate object' do
      dupe_query = @query.merge(:author => 'dkubb')
      @query.object_id.should_not == dupe_query.object_id
      @query.merge(:author => 'dkubb').should == dupe_query
    end
  end

  describe '#==' do
    before do
      @query = DataMapper::Query.new(repository(:mock), Article)
    end

    describe 'should be equal' do
      it 'when other is same object' do
        @query.update(:author => 'dkubb').should == @query
      end

      it 'when other has the same attributes' do
        other = DataMapper::Query.new(repository(:mock), Article)
        @query.object_id.should_not == other.object_id
        @query.should == other
      end

      it 'when other has the same conditions sorted differently' do
        @query.update(:author => 'dkubb')
        @query.update(:title  => 'On DataMapper')

        other = DataMapper::Query.new(repository(:mock), Article, :title => 'On DataMapper')
        other.update(:author => 'dkubb')

        # query conditions are in different order
        @query.conditions.should == [ [ :eql, Article.properties[:author], 'dkubb'         ], [ :eql, Article.properties[:title],  'On DataMapper' ] ]
        other.conditions.should  == [ [ :eql, Article.properties[:title],  'On DataMapper' ], [ :eql, Article.properties[:author], 'dkubb'         ] ]

        @query.should == other
      end
    end

    describe 'should be different' do
      it 'when other model is different than self.model' do
        @query.should_not == DataMapper::Query.new(repository(:mock), Comment)
      end

      UPDATED_OPTIONS.each do |attribute,value|
        it "when other #{attribute} is different than self.#{attribute}" do
          @query.should_not == DataMapper::Query.new(repository(:mock), Article, attribute => value)
        end
      end

      it 'when other conditions are different than self.conditions' do
        @query.should_not == DataMapper::Query.new(repository(:mock), Article, :author => 'dkubb')
      end
    end
  end
end
