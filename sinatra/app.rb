require 'rubygems'
require 'sinatra'
require 'json'

require 'lib/default.rb'

get '/' do
	'Hello world!'
end

navigators = {}

configure do
	navigators['default'] = DefaultNavigator.new()
end

options '/navi/:algorithm' do |alg|
	cross_origin
end

post '/navi/:algorithm' do |alg|
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

