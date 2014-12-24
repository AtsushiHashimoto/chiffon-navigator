module Navi
    class CheckWithNoise
				@@sym = :Noise

        def initialize(app)
            @app = app
				end
				def log_error(str)
					raise str
				end
				
#######################
# cwn_data
#######################
=begin
 {:noise_researve => {substep_id=>{:slip=>$ex_input, :jump=>$ex_input, :jump_delay=>sec} } }
 $ex_input is external input for jump command
 $sec is number that indicates delay for jump.
=end

		
##########################
# CheckWithNoise External Input
##########################
				def route(session_data,ex_input)
					session_data[:progress][@@sym],change = self.init(session_data)
				
					case ex_input[:action][:name]
						when 'set_param'
							return self.set_param(session_data,ex_input,change)
						when 'check'
							return self.check(session_data,ex_input,change)
						else
							log_error "Unknown action for ObjectAccess algorithm: '#{ex_input[:action][:name]}' is directed by external input."
					end						
				end
				

############################
# CheckWithNoise Initialize State
############################

				def init(session_data)
						recipe = session_data[:recipe]
						change = Recipe::StateChange.new

						unless session_data[:progress].include?(@@sym) then
							cwn_data = Hash.new
							change[@@sym] = cwn_data.deep_dup
						else
							cwn_data = session_data[:progress][@@sym]
							change[@@sym] = ActiveSupport::HashWithIndifferentAccess.new
						end

						return cwn_data,change
				end
						
############################
# Touch/Release process
############################
				def check(session_data,ex_input,change)
					STDERR.puts "check (with noise)!"
					
					cwn_data = session_data[:progress][@@sym]
					substep_id = ex_input[:action][:target]
					
					if cwn_data[:noise_reserve][substep_id] then
							noise_pat = cwn_data[:noise_reserve][substep_id]
							
					end


					state, temp = @app.navi_algorithms['default'].check(session_data,ex_input)
					change.deep_merge!(temp)
					return state,change
				end
				
				def set_param(session_data,ex_input,change)
					
					return "sucess", change 
				end
		end
end