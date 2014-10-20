require 'sinatra/base'

module Helpers
    module FileIO
        extend Sinatra::Extension


        def self.registered(app)
        app.helpers FileIO
        end


    #    def valid?(elem)
    #        return false if nil == elem
    #        return false if elem.empty?
    #        return true
    #    end
        def generate_progress_diff_filename(session_dir,iter_index)
            filename = settings.progress_diff_file_template.gsub(settings.progress_diff_file_template_replace,"%03d"%iter_index)
            return "#{session_dir}/#{filename}"
        end
        
        def check_posted_data(json_data)
            log_error("No session_id is directed in the posted data.") unless json_data.include?("session_id")
            log_error("No situation is directed in the posted data.") unless json_data.include?("situation")
            json_data["situation"].upcase!
            return true
        end
        
        def load_json_file(file)
            hash_data = nil
            open(file,"r"){|io|
                hash_data = JSON.load(io,nil,{:symbolize_names => true})
            }
            hash_data = {} if nil == hash_data
            return hash_data
        end
        
        def save_json_file(hash_data,file)
            return if nil == hash_data or hash_data.empty?
            open(file,"w"){|io|
                io.puts(JSON.pretty_generate(hash_data))
            }
        end

        def session_lock(session_id)
            session_dir = "#{settings.root}/#{settings.record_dir}/#{session_id}"
            system("mkdir -p #{session_dir}") unless File.exist?(session_dir)
            lock_file = "#{session_dir}/lockfile"
            unless File.exist?(lock_file)
                system("touch #{lock_file}")
            end
            fo = open(lock_file, "w")
            fo.flock(File::LOCK_EX)
            return fo
        end
        
        def session_unlock(fo)
            fo.flock(File::LOCK_UN)
            fo.close
        end
    
    end
end