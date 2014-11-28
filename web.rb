require 'sinatra'
require 'sinatra/json'
require 'data_mapper'
require 'json'
require 'logger'
require 'multimap'
require 'pg'
require 'rest-client'

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

# Data model
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

  def save_entry(sig, entry_body, submitted_at = Time.now)
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
    success = entry.update!(:body => entry_body, :submitted_at => submitted_at)
    if success
      entry
    else
      nil
    end
  end

  def send_email(from, to, subject, body)
    RestClient.post "https://api:#{ENV['MAILGUN_API_KEY']}"\
      "@api.mailgun.net/v2/commentarios.net/messages",
      :from => "Commentarios.net <#{from}@commentarios.net>",
      :to => to,
      :subject => subject,
      :text => body
  end
end

get '/' do
  "Hello from LifeJournal"
end

# ===========
# TODO: under auth (start)
# ===========
get '/users' do
  users = User.all(:order => [:email_address])
  {:users => users}.to_json
end

get '/users/:email_address' do |email_address|
  User.first(:email_address => email_address).to_json
end

get '/users/:email_address/entries' do |email_address|
  u = User.first(:email_address => email_address)
  Entry.all(:user => u).to_json
end

post '/users' do
  User.create(:email_address => @data['email_address']).to_json
end

get '/entries' do
  Entry.all(:order => [:user_id]).to_json
end

# ===========
# under auth (end)
# ===========

post '/incoming' do
  logger.info "#{params}"

  sender              = params['sender']
  recipient           = params['recipient']
  sig = recipient.sub(/<(.*)@.*/, '\1')
  body_without_quotes = params['stripped-text'] || ''
  submitted_at        = params['Date']

  logger.info "in_reply_to = #{in_reply_to}, \nsig = #{sig}, \nuser_email = #{sender}, \ntext = #{body_without_quotes}, \nsubmitted_at = #{submitted_at}"

  entry = save_entry(sig, body_without_quotes)
  unless entry
    logger.error "Entry #{sig} was not updated"
    halt 500, "Entry #{sig} was not updated"
  end
end

# save/update an existing entry
post '/entries/:signature' do |sig|
  #parse incoming json data
  logger.debug "sig = #{sig}, data = #{@data}"

  entry = save_entry(sig, @data['entry_body'])
  unless entry
    logger.error "Entry #{sig} was not updated"
    halt 500, "Entry #{sig} was not updated"
  end
  entry.to_json
end

# create an empty "entry" and send email reminder
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

  #send reminder email
  send_email(entry.signature, u.email_address, "It's #{entry.for_date.strftime('%A, %b %-d')} - How did your day go?", "Just reply to this email with your entry")

  #return
  entry.to_json
end


#TODO 2. Cron for triggering emails
#TODO 3. Import all entries
