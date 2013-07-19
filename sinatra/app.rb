require 'rubygems'
require 'sinatra'
require 'json'

require 'lib/default.rb'

get '/' do
	'Hello world!'
end

navigators = {}

configure do
	# add navigator algorithm class here
	navigators['default'] = DefaultNavigator.new()
end


options '/navi/:algorithm' do |alg|
	# headers against Cross Domain Request (CORS)
	headers "Access-Control-Allow-Origin" => "*"
	headers "Access-Control-Allow-Credentials" => "true"

	headers "Access-Control-Allow-AMAethods" => "POST, OPTIONS"
	headers "Access-Control-Max-Age" => "7200"
	headers "Access-Control-Allow-Headers" => "x-requested-with, x-requested-by"
end

post '/navi/:algorithm' do |alg|
	headers "Access-Control-Allow-Origin" => "*"
	headers "Access-Control-Allow-Credentials" => "true"

	request.body.rewind
	json_data = JSON.parse(request.body.read) 
	prescription = {}
	if !navigators.include?(alg) then
		# Error!!
	elsif
		prescription = navigators[alg].counsel(json_data)
	end

#	validate(prescription)

#	prescription = json_data # only for debug. remove it for developing counsel
	return JSON.generate(prescription)
end

