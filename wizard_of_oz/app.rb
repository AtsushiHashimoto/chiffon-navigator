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
require "#{File.dirname(__FILE__)}/helpers.rb"

class WOZ < Sinatra::Base
    helpers Sinatra::MyHelpers


    configure do
        STDERR.puts File.dirname(__FILE__)
        STDERR.puts File.exist?("#{File.dirname(__FILE__)}/helpers.rb")
        settings.root = "#{File.dirname(settings.root)}" # root
        # constant values
        set :MyConfFile, "config.yml"
        set :views, "#{File.dirname(__FILE__)}/views"
        set :js_dir, "javascript"
        set :css_dir, "css"
        
        # load Configure File.
        register Sinatra::ConfigFile
        config_file "#{settings.root}/#{settings.MyConfFile}"

        register Sinatra::Reloader
    end

    before do
        @title = "Chiffon WOZ Interface"
        @receiver_url = settings.viewer_url + "/receiver"
        @logger_url = settings.viewer_url + "/logger"
        @prescription_url = "/navi/latest_prescription"
    end

    get '/woz/session_id/:username' do |username|
        session_dirs = Dir.entries("#{settings.root}/#{settings.record_dir}")
        session_dirs = session_dirs.find_all{|v| v=~ /^#{username}-.*$/}
        return session_dirs.sort.reverse.join("\n")
    end

    get '/woz/recipe/:session_id' do |session_id|
				recipe = File.open("#{settings.root}/#{settings.record_dir}/#{session_id}/recipe.xml","r").read.encode('ISO-8859-1','utf-8')		
				unless recipe.empty? then
					return recipe
				end
				
				status 404
				headers
				body "File Not Found"
    end

    get '/woz/:username/:num' do |username,num|
        headers "Access-Control-Allow-Origin" => "*"
        headers "Access-Control-Allow-Credentials" => "true"
        status, header, body = call env.merge("PATH_INFO" => "/woz/session_id/#{username}").merge("REQUEST_METHOD" => "GET")
        
        session_list = body[0].split("\n")
        num = num.to_i
        return "ERROR: no session as directed!" if session_list.size <= num
        
        redirect "/woz/#{session_list[num]}", 303
    end

    get '/woz/:session_id' do |session_id|
        headers "Access-Control-Allow-Origin" => "*"
        headers "Access-Control-Allow-Credentials" => "true"
        
        @session_id = session_id
        raise "invalid session_id?" unless session_id =~ /(.+?)-.*/
        
        @user = $1
        
				status = nil
				iteration = 0
				while 200 != status do
					status,header,body = call env.merge("PATH_INFO" => "/woz/recipe/#{@session_id}").merge("REQUEST_METHOD" => "GET")
					iteration = iteration + 1
					return [404,"","File Not Found"] if iteration > 300
				end
        @recipe = Nokogiri::XML(body[0])

        haml :index
    end

end