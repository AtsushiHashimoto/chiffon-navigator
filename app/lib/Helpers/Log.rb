require 'sinatra/base'

module Helpers
    module Log
        extend Sinatra::Extension
        
        def log_level
            case settings.log_level
                when :info then
                    return Logger::INFO
                when :warn then
                    return Logger::WARN
                when :error then
                    return Logger::ERROR
                when :debug then
                    return Logger::DEBUG
                when :fatal then
                    return Logger::FATAL
                else
                    return Logger::WARN
            end
        end


        def self.registered(app)
        app.helpers Log
        end

        def parse_caller(call)
            regex = "^(.+?):(\d+)(?::in `(.*)')?"
            if /regex/ =~ call
                file = $1
                line = $2.to_i
                method = $3
                [file, line, method]
            end
        end


        def log_error(str)
            file,line,method = parse_caller(caller.first)
            error_str = "At [#{file}:#{line} in function #{method}]: #{str}"
            raise error_str
        end
        
        def create_session_logger(file)
            session_logger = Logger.new(file)
            session_logger.level = log_level
            session_logger.datetime_format = settings.datetime_format
            return session_logger
        end
        
        
    end
end