require 'rubygems'
require 'sinatra'
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
	data = request.body.read

	prescription;
	if !navigator.include?(alg) then
		# Error!!
	elsif
		prescription = navigator[alg].counsel(data)
	end

#	validate(prescription)

	return prescription
end

