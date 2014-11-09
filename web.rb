require 'sinatra'
require 'sinatra/json'
require 'data_mapper'
require 'pg'

DataMapper.setup(:default, ENV['DATABASE_URL'] || 'postgres://localhost/mydb')
#'postgres://user:password@hostname/database'

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
  property :submitted_at, DateTime
  belongs_to :user
end

class User
  has n, :entries
end

DataMapper.finalize.auto_upgrade!

get '/' do
  json :msg => "Hello Sinatra"
end

get '/users' do
  users = User.all(:order => [:email_address])
  json :users => users
end

post '/users' do
  u = User.new(params[:user])
  if u.save
    json :user => u
  else
    json :error => 'could not save'
  end
end


