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

helpers do
=begin
  def setup_mailgun_routes
    # requires multimap, rest-client
    data = Multimap.new
    data[:priority] = 0
    data[:description] = "Incoming post"
    data[:expression]  = "match_recipient('(.*)@commentarios.net')"
    data[:action]      = "forward('https://boiling-headland-6049.herokuapp.com/entries/\1')"
    data[:action]      = "stop()"
    RestClient.post "https://api:key-asfasdf@api.mailgun.net/v2/routes", data
  end
=end
  
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

class IncomingPost
  include DataMapper::Resource
  property :id, Serial
  property :created_at, DateTime
  property :fullpath, Text
  property :referer, Text
  property :raw_body, Text
end

class User
  has n, :entries
end

DataMapper.finalize.auto_upgrade!

before do
  content_type :json
end

before :method => :post do
  @raw_body = request.body.read
  #record the post
  incoming_post = IncomingPost.create(:fullpath => request.fullpath, :referer => request.referer, :raw_body => @raw_body)
  logger.debug "incoming_post = #{incoming_post.id}"
  
  @data = nil
  begin
    @data = JSON.parse(@raw_body)
  rescue => e
    # do nothing with the error
  end
end

before :method => :put do
  begin
    @data = JSON.parse(request.body.read)
  rescue => e
    # do nothing with the error
  end
end

get '/' do
  json :msg => "Hello from LifeJournal"
end

get '/users' do
  User.all(:order => [:email_address])
end

get '/user/:email_address' do |email_address|
  User.first(:email_address => email_address)
end

get '/user/:email_address/entries' do |email_address|
  u = User.first(:email_address => email_address)
  Entry.all(:user => u)
end

post '/users' do
  User.create(:email_address => @data['email_address'])
end

get '/entries' do
  Entry.all(:order => [:user_id])
end

post '/incoming' do
  logger.info "#{params.keys}"
  sender              = params['Sender']
  recipient           = params['Recipient']
  in_reply_to         = params['In-Reply-To'] || ''
  sig = in_reply_to.sub("<(.*)@.*", "\1")
  body_plain          = params['body-plain'] || ''
  body_without_quotes = params['stripped-text'] || ''
  submitted_at        = params['Date']
  logger.info "in_reply_to = #{in_reply_to}, \nsig = #{sig}, \nuser_email = #{sender}, \ntext = #{body_without_quotes}, \nsubmitted_at = #{submitted_at}, \nbody_plain = #{body_plain}"
end

# save/update an existing entry
post '/entries/:signature' do |sig|

  #parse incoming json data
  logger.debug "sig = #{sig}, data = #{@data}"

  unless sig
    logger.error "sig not found"
    halt 404, "Missing parameter: signature"
  end

  entry = Entry.first(:signature => sig)
  unless entry
    logger.error "Entry #{sig} not found"
    halt 404, "Entry #{sig} not found"
  end

  logger.debug "Updating entry: #{entry.to_json}"
  success = entry.update!(:body => @data['entry_body'], :submitted_at => Time.now)
  if success
    entry
  else
    logger.error "Entry #{sig} was not updated"
    halt 500, "Entry #{sig} was not updated"
  end
end

# create an empty "entry"
post '/entries' do

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
  entry
end


#TODO 1. Add auth for the user methods
#TODO 2. Cron for triggering emails
#TODO 3. Import all entries
#TODO 4. Hookup mailgun incoming email with update
