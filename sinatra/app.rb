require 'rubygems'
require 'sinatra'


get '/' do
	'Hello world!'
end

options '/navi/:algorithm' do |alg|
	cross_origin
end

post '/navi/:algorithm' do |alg|
	request.body.rewind
	data = request.body.read

	output = "Algorithm: #{alg}<br>"
	output += "JSON: #{data}"
	return output
end

