require 'sinatra'
require 'sinatra/json'
require 'data_mapper'
require 'json'
require 'logger'
require 'pg'

DataMapper.setup(:default, ENV['DATABASE_URL'] || 'postgres://localhost/mydb')
configure :development do
  set :logging, Logger::DEBUG
end
configure :production do
  set :logging, Logger::INFO
end

set(:method) do |m|
  m = m.to_s.upcase
  condition { request.request_method == m }
end

before :method => :post do
  @data = JSON.parse(request.body.read)
end

before :method => :put do
  @data = JSON.parse(request.body.read)
end

helpers do
  # Generates a random string of 10 characters using 1-9,A-Z,a-z
  # inspired by Paul Tyma
  def generate_signature
    ranges = [[49,57], #ascii 1-9
              [65,90], #ascii A-Z
              [97,122]] #ascii a-z
    ret_val = ''
    10.times { |i|
      j = Random.rand(3)
      k = Random.rand( ranges[j][1] - ranges[j][0] )
      ret_val += (k + ranges[j][0]).chr
    }
    ret_val
  end
end

class User
  include DataMapper::Resource
  property :id, Serial
  property :email_address, Text
end

class Entry
  include DataMapper::Resource
  property :id, Serial
  property :signature, Text
  property :body, Text
  property :created_at, DateTime
  property :for_date, DateTime
  property :submitted_at, DateTime
  belongs_to :user
end

class User
  has n, :entries
end

DataMapper.finalize.auto_upgrade!

get '/' do
  json :msg => "Hello from LifeJournal"
end

get '/users' do
  users = User.all(:order => [:email_address])
  json :users => users
end

get '/user/:email_address' do |email_address|
  u = User.first(:email_address => email_address)
  json :user => u
end

post '/users' do
  u = User.new(params[:user])
  if u.save
    json :user => u
  else
    json :error => 'could not save'
  end
end

# update an existing entry
put '/entries/:id' do |id|
  content_type :json

  #parse incoming json data
  logger.debug "id = #{id}, data = #{@data}"

  entry = Entry.get!(id)
  unless entry
    logger.error "Entry #{id} not found"
    halt 404, "Entry #{id} not found"
  end

  logger.debug "Updating entry: #{entry.to_json}"
  success = entry.update!(:body => @data['entry_body'])
  if success
    json :entry => entry
  else
    logger.error "Entry #{id} was not updated"
    halt 500, "Entry #{id} was not updated"
  end

end

# create an empty "entry"
post '/entries' do
  content_type :json

  #parse incoming json data
  logger.debug "data = #{@data}"

  #default for_date
  @data['for_date'] = Time.now.strftime("%Y-%m-%d") unless @data['for_date']
  logger.debug "email = #{@data['email_address']}, for_date = #{@data['for_date']}"
  unless @data['email_address']
    logger.error 'No user email address found'
    halt 400, {:error => 'No user email address found'}.to_json
  end

  #get user_id from email
  u = User.first(:email_address => @data['email_address'])
  unless u
    logger.error "User not found: #{@data['email_address']}"
    halt 404, {:error => "User not found: #{@data['email_address']}"}.to_json
  else
    logger.debug "Found user: #{u.to_json}"
  end

  #generate signature
  sig = generate_signature
  logger.debug "sig = #{sig}"

  #create
  entry = Entry.create(
    :signature => sig,
    :for_date => DateTime.strptime(@data['for_date'], "%Y-%m-%d"),
    :user => u,
    :created_at => DateTime.now
  )
  logger.debug "Saved entry: #{entry.to_json}"

  #return
  json :entry => entry
end

put '/entries/:id' do |id|
  content_type :json

  #parse incoming json data
  request_body = request.body.read
  logger.debug "body = #{request_body}"
  data = JSON.parse(request_body)
  logger.debug "data = #{data}"
  entry = Entry.get!(id)

end

#TODO 1. Add auth for the user methods
#TODO 2. Cron for triggering emails
#TODO 3. Import all entries
#TODO 4. Hookup mailgun incoming email with update
