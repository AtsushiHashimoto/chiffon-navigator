#coding: utf-8
require 'nkf'
require 'logger'
require 'rubygems'
require 'sinatra/base'
require 'sinatra/reloader'
require 'sinatra/config_file'
require 'sinatra/multi_route'
require 'json'
require 'nokogiri'
require 'active_support/all'
require 'net/http'
require 'uri'

#require "#{File.dirname(__FILE__)}/helpers.rb"

# 認識システムとの連携用パス /recognizer/* のrouting をするクラス
class RecognizerSupport < Sinatra::Base
		register Sinatra::MultiRoute
    helpers Sinatra::MyHelpers

    configure do
				settings.root = "#{File.dirname(settings.root)}" # root
				# constant values
				set :MyConfFile, "config.yml"
#				set :views, "#{File.dirname(__FILE__)}/views"
#				set :js_dir, "javascript"
#				set :css_dir, "css"
				
				# load Configure File.
				register Sinatra::ConfigFile
				config_file "#{settings.root}/#{settings.MyConfFile}"

        register Sinatra::Reloader
				
    end

    get '/recognizer/:session_id/objects' do |session_id|
				recipe_file = "#{settings.root}/#{settings.record_dir}/#{session_id}/recipe.xml"
				unless File.exist?(recipe_file) then
					return 404
				end
				recipe = Nokogiri.XML(File.open(recipe_file,"r").read.encode('ISO-8859-1','utf-8'))
				objects = []
				for elem in recipe.xpath('//object') do
						name = elem[:name]
						id = elem[:id]
						objects << {'name'=>name, 'id'=>id}
				end
				recipe_name = recipe.root[:title]
				for elem in recipe.xpath('//step') do
						id = elem[:id] 
						next unless id
						name = "#{recipe_name}:#{id}"
						objects << {'name'=>name,'id'=>id}
				end
				for elem in recipe.xpath('//event') do
						id = elem[:id]
						next unless id
						name,suffix = id.split('_')
						next unless 'utensil' == suffix
						objects << {'name'=>name, 'id'=>id}
				end

        return "\n#{objects.to_json}"
    end
				
		get '/recognizer/model/:model/:id' do |model,id|
				model_file = "#{settings.root}/#{settings.model_dir}/#{model}/#{id}.model"
				if params[:type] == 'file' then
						unless File.exist?(model_file) then
							return 404
						end
						send_file model_file
				else
					return "" unless File.exist?(model_file)
					return File.open(model_file,"r").read
				end
		end
		
		ReservedParamKeys = ["splat","captures","session_id","classifier","operation"]
		route :get, :post, '/recognizer/:session_id/:classifier/:operation' do |session_id, clf_algo, op|
			# get recipe
			recipe_file = "#{settings.root}/#{settings.record_dir}/#{session_id}/recipe.xml"
			STDERR.puts recipe_file
			unless File.exist?(recipe_file) then
				return 404
			end
			recipe = Nokogiri.XML(File.open(recipe_file,"r").read.encode('ISO-8859-1','utf-8'))
			group = recipe.root['id']
			
			json_data = params.delete_if{|k,v| ReservedParamKeys.include?(k)}

			if json_data.include?('group') then
				begin
					json_data['group'] = JSON.parse(json_data['group'])
					raise "group must be Array, but #{json_data['group'].class} is input." 					if !json_data['group'].kind_of?(Array)
				rescue
					json_data['group'] = [json_data['group']]
				end
				json_data['group'] << group
			else
				json_data['group'] = [group]
			end
			
			if json_data.include?('feature') then
				begin
					json_data['feature'] = JSON.parse(json_data['feature'])
					raise "group must be Array, but #{json_data['group'].class} is input." 					if !json_data['feature'].kind_of?(Array)
				rescue
					json_data['feature'] = [json_data['feature']]
				end					
			end
			
			json_data_s = json_data.to_json
			query = "json_data=#{URI.encode(json_data_s)}"
			begin
				Net::HTTP.start(settings.serv4recog_host,
												settings.serv4recog_port){|http|
					uri_path = "/ml/#{settings.serv4recog_db}/#{clf_algo}/#{op}"
					STDERR.puts uri_path
					STDERR.puts query
					response = http.post(uri_path,query)
				}
			rescue
				return '{"status":"error","message":"failed to communicate with serv4recog"}'
			end
			STDERR.puts response.body
			return response.body
		end

end