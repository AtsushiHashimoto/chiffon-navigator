#coding: utf-8
require 'nkf'
require 'logger'
require 'rubygems'
require 'sinatra/base'
require 'sinatra/reloader'
require 'sinatra/config_file'
require 'json'
require 'active_support/all'

$LOAD_PATH.push(File.dirname(__FILE__))


# Helper
require 'Helpers/FileIO.rb'
require 'Helpers/Log.rb'
require 'Helpers/Utils.rb'


# Navi Basic Modules
require 'Navi/Base.rb'

# Navi Extension Modules
require 'Navi/Default.rb'
require 'Navi/ObjectAccess.rb'
require 'Navi/ObjectAccessFuzzy.rb'
require 'Navi/CheckWithNoise.rb'


# Recipe Class
require 'Recipe/Recipe.rb'
require 'Recipe/Progress.rb'



class ChiffonNavigator < Sinatra::Base
    register Helpers::Log
    register Helpers::FileIO
    register Navi::Base
    
    # enable error routing in development environment.
    set :show_exceptions, false
    
    

    # session_data
    set :session_databank, {}
    set :navi_algorithms, {}
		
    configure do
        settings.root = "#{File.dirname(File.dirname(settings.root))}" # root should not be /lib

        # constant values
        set :MyConfFile, "config.yml"

        # load Configure File.
        register Sinatra::ConfigFile
        config_file "#{settings.root}/#{settings.MyConfFile}"


        set :error_logger, Logger.new("#{settings.root}/#{settings.error_log}")
        enable :logging
        # set your Module to '/navi/:algorithm' and/or {"navigator":":algorithm",...} in external input
        # see also './lib/Navi/Default.rb'
        settings.navi_algorithms["default"] = Navi::Default.new(self)
				settings.navi_algorithms["object_access"] = Navi::ObjectAccess.new(self)
				settings.navi_algorithms["object_access_fuzzy"] = Navi::ObjectAccessFuzzy.new(self)
				settings.navi_algorithms["check_with_noise"] = Navi::CheckWithNoise.new(self)
        ## add your algorithm module to 'navi_algorithm' here! ##
	
        settings.error_logger.datetime_format = settings.datetime_format
        settings.error_logger.level = Logger::ERROR
    end

    configure :development do
        register Sinatra::Reloader
    end


    # main route to communicate with viewer.
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
				
        #        return "default_navigation\n"
        request.body.rewind
        body_read = request.body.read.encode('ISO-8859-1','utf-8')
        json_data = JSON.parse(body_read)
        #        STDERR.puts "Request: #{json_data}"
        prescription = {}

        lock_file = nil
        session_logger = nil
        
        begin
            check_posted_data(json_data)
            session_id =json_data["session_id"]
            lock_file = session_lock(session_id)
            
            if settings.session_databank.keys.include?(session_id) then
                session_data = settings.session_databank[session_id]

                session_data[:json_data] = json_data
                session_data[:alg] = settings.navi_algorithms[alg]

                session_dir = session_data[:session_dir]
                session_logger = session_data[:logger]
                progress = session_data[:progress]
                progress_file = "#{session_dir}/#{settings.progress_file}"
            else
                session_dir = "#{settings.root}/#{settings.record_dir}/#{session_id}"

                progress_file = "#{session_dir}/#{settings.progress_file}"
                system("touch #{progress_file}")
                progress = load_json_file(progress_file).to_progress

                # prepare session logger
                session_logger = create_session_logger("#{session_dir}/#{settings.session_log}")
                session_logger.debug "default_navigation called. session_dir: #{session_dir}"

                recipe_file ="#{session_dir}/#{settings.recipe_file}"
                recipe = Recipe::Recipe.new
                unless "START" == json_data["situation"] then
                    log_error("The session did not start with 'START' situation.") unless File.exist?(recipe_file)
                    recipe = Nokogiri.XML(File.open(recipe_file,"r"))
                end
                # bind up session local variables
                session_data = {}
                session_data[:json_data] = json_data
                session_data[:session_dir] = session_dir
                session_data[:progress] = progress
                session_data[:logger] = session_logger
                session_data[:recipe] = recipe
                session_data[:alg] = settings.navi_algorithms[alg]
                session_data[:id] = session_id
                settings.session_databank[session_id] = session_data

            end

            log_error "unknown algorithm '#{alg}' was designated." unless settings.navi_algorithms.include?(alg)
            session_logger.info json_data

						if session_data.include?(:progress) and session_data[:progress].include?(:state)
							prev_cur_ss = current_substep(session_data[:recipe],session_data[:progress][:state])
						else
							prev_cur_ss = nil
						end


            # counseling
            case json_data["situation"]
                when "NAVI_MENU" then
                    status, change = navi_menu(session_data)
                when "EXTERNAL_INPUT" then
                    status, change = external_input(session_data,settings.navi_algorithms)
                when "CHANNEL" then
                    status, change = channel(session_data)
                when "CHECK" then
                    status, change = check(session_data)
                when "START" then
                    log_error("START is called more than twice") if File.exist?("#{session_dir}/#{recipe_file}")
                    status, change = start(session_data)
                when "END" then
                    call env.merge("PATH_INFO" => "/navi/clear/guest-2014.08.06_21.27.10.284063").merge("REQUEST_METHOD" => "GET")
                    status, change = ["success",Recipe::StateChange.new]
                when "PLAY_CONTROL" then
                    status, change = _play_control(session_data)
                else
                log_error("unknown situation '#{json_data['situation']}' is directed.")
            end
						
						cur_ss = current_substep(session_data[:recipe],change[:state])
						if prev_cur_ss and cur_ss and prev_cur_ss.id!=cur_ss.id then
								status, change = stop_all_medias(session_data[:recipe], session_data[:progress], prev_cur_ss, change)
								#								STDERR.puts temp
								#								change.deep_merge!(temp)
						end

            # do not save delta when "undo" or "redo" has been input
            do_save_delta = (-1 == change[:iter_index]) ? true : false

            # assert(progress == session_data[:progress])
            delta = Recipe::Delta.new
            session_logger.debug "Change: #{change}"
            progress.update!(change,delta)

            unless delta.empty? then
                #            session_logger.info status
                session_logger.debug "Delta: #{delta.to_array.to_s}"
                if do_save_delta then
                    save_json_file(delta.to_array,generate_progress_diff_filename(session_dir,progress[:iter_index]))
                    next_delta_file = generate_progress_diff_filename(session_dir,progress[:iter_index]+1)
                    `rm -f #{next_delta_file}` if File::exist?(next_delta_file)
                end
            
                save_json_file(progress,progress_file)
                session_logger.debug "Progress: #{progress}"
                
                prescription['status'] = status
                prescription['body'] = create_prescription(delta,progress)
            else
                prescription = {'status'=>status,'body'=>[]}
            end
            
        rescue => ex
            
            # エラー処理  ex.message
            short_message = "'" + ex.message + "' at " + ex.backtrace[0]
            message = ex.message + "\n" + ex.backtrace.join("\n")
            settings.error_logger.error(message)
            session_logger.error(message) unless session_logger==nil

            prescription['status'] = 'internal error'
            prescription['body'] = short_message
        end
        session_logger.info "Prescription: #{JSON.generate(prescription)}" unless session_logger==nil
        #        session_logger.close unless session_logger==nil
        session_unlock(lock_file) unless nil==lock_file
        return "\n"+ JSON.generate(prescription) + "\n"
    end

    get '/navi/clear/:session_id' do |session_id|
        headers "Access-Control-Allow-Origin" => "*"
        headers "Access-Control-Allow-Credentials" => "true"
        return "no session data for Session #{session_id} has been found.\n" unless session_databank.keys.include?(session_id)
        
        lock_file = session_lock(session_id)
        session_databank.delete(session_id)
        session_unlock(lock_file)
        return "session data for Session #{session_id} has been cleared successfully.\n"
    end

    get '/navi/progress/:session_id' do |session_id|
        headers "Access-Control-Allow-Origin" => "*"
        headers "Access-Control-Allow-Credentials" => "true"

        session_dir = "#{settings.root}/#{settings.record_dir}/#{session_id}"
        progress_file = "#{session_dir}/#{settings.progress_file}"
        raise "There is no progress file directed by the session id." unless File.exist?(progress_file)
        File.open(progress_file,'r').read
    end

    get '/navi/delta/:iter_index/:session_id' do |iter_index,session_id|
        headers "Access-Control-Allow-Origin" => "*"
        headers "Access-Control-Allow-Credentials" => "true"

        session_dir = "#{settings.root}/#{settings.record_dir}/#{session_id}"
        delta_file = generate_progress_diff_filename(session_dir,iter_index);
        raise "There is no delta file directed by the session id." unless File.exist?(delta_file)
        File.open(delta_file,'r').read
    end

    get '/navi/latest_prescription/:session_id' do |session_id|
        headers "Access-Control-Allow-Origin" => "*"
        headers "Access-Control-Allow-Credentials" => "true"

				status,header,body = call env.merge("PATH_INFO" => "/navi/progress/#{session_id}").merge("REQUEST_METHOD" => "GET")
				return [] if body[0].empty?
				progress = JSON::parse(body[0],{:symbolize_names => true}).to_progress

				delta = Recipe::Delta.new
				delta.after = progress
				return JSON.generate(create_prescription(delta,progress))

    end




end

