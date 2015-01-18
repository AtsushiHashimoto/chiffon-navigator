#coding: utf-8
require 'nkf'
require 'logger'
require 'rubygems'
require 'sinatra/base'
require 'sinatra/reloader'
require 'sinatra/config_file'
require 'json'
require 'nokogiri'
require 'active_support/all'
#require "#{File.dirname(__FILE__)}/helpers.rb"

# 認識システムとの連携用パス /recognizer/* のrouting をするクラス
class RecognizerSupport < Sinatra::Base
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

end