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
 {:noise_reserve => {substep_id=>{:slip=>$ex_input, :jump=>$ex_input, :jump_delay=>sec} } }
 $ex_input is external input for jump command
 $sec is number that indicates delay for jump.
=end

		
##########################
# CheckWithNoise External Input
##########################
				def route(session_data,ex_input)
					session_data[:progress][@@sym],change = self.init(session_data)
				
					case ex_input[:action][:name]
						when 'set'
							return self.set_param(session_data,ex_input,change)
						when 'check'
							return self.check(session_data,ex_input,change)
						else
							log_error "Unknown action for CheckWithNoise algorithm: '#{ex_input[:action][:name]}' is directed by external input."
					end						
				end
				

############################
# CheckWithNoise Initialize State
############################

				def init(session_data)
						change = Recipe::StateChange.new

						if session_data[:progress].include?(@@sym) then
							cwn_data = session_data[:progress][@@sym].with_indifferent_access
							change[@@sym] = ActiveSupport::HashWithIndifferentAccess.new
							change[@@sym][:noise_reserve] = ActiveSupport::HashWithIndifferentAccess.new
						else
							cwn_data = {:noise_reserve=>{}}
							change[@@sym] = cwn_data.deep_dup
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


					state, temp = @app.navi_algorithms['default'].check(session_data,ex_input)
					change.deep_merge!(temp)
					
					STDERR.puts "#{__FILE__} at line #{__LINE__}"					
					if ex_input[:action].include?(:value) and ex_input[:action][:value]==false then
						return state, change
					end
					STDERR.puts "#{__FILE__} at line #{__LINE__}"					
					
					STDERR.puts cwn_data
					STDERR.puts cwn_data[:noise_reserve]
					STDERR.puts cwn_data[:noise_reserve][substep_id.to_s]
					
					return state, change if is_empty_noise(cwn_data[:noise_reserve][substep_id])
					
					STDERR.puts "#{__FILE_} at line #{__LINE__}"					
					noise_pat = cwn_data[:noise_reserve][substep_id]
					STDERR.puts noise_pat
					STDERR.puts noise_pat['slip']
					if noise_pat.include?('slip') then
						STDERR.puts "#{__FILE__} at line #{__LINE__}"					
						false_target = noise_pat[:slip][:false_target]
						ex_input['action'] = {'name'=>'jump','target'=>false_target,'check'=>'false'}
						puts ex_input
						state, temp = @app.navi_algorithms['default'].jump(session_data,ex_input)
						change.deep_merge!(temp)
						STDERR.puts "#{__FILE__} at line #{__LINE__}"					
					end

					
					return state,change
				end
				
				def set_param(session_data,ex_input,change)
					recipe = session_data[:recipe]
					ref_progress = session_data[:progress]

					substep_id = ex_input[:action][:target]
					noise_reserve = session_data[:progress][@@sym][:noise_reserve][substep_id]
					unless noise_reserve then
						noise_reserve = {}
					end
					noise = ex_input[:action][:noise]
					noise_type = noise[:type]
					
					
					STDERR.puts noise
					if noise.include?(:direction) then
						false_target = choose_false_target(ref_progress, recipe, noise[:direct], substep_id)
						noise_reserve[noise_type] = {:false_target=>false_target}
					
						
						if noise_type == 'jump' then
							noise_reserve[noise_type][:delay] = noise[:delay].to_f					
						end
						change[@@sym][:noise_reserve][substep_id] = noise_reserve
						
					else
					#						STDERR.puts "clear"
						change[@@sym][:noise_reserve][substep_id][noise_type] = :clear if change[@@sym].include?(substep_id) and change[@@sym][substep_id].include?(noise_type)
					end
					return "sucess", change 
				end
				
				
				def choose_false_target(ref_progress, recipe, direction, right_tar)
					'substep03_02'
				end
				
				def is_empty_noise(noise)
					STDERR.puts "#{__FILE__} at line #{__LINE__}"					
					STDERR.puts noise
					return true unless noise
					STDERR.puts "#{__FILE__} at line #{__LINE__}"					
					return true if noise.empty?
					STDERR.puts "#{__FILE__} at line #{__LINE__}"	
					flag = true
					for noise_type, data in noise do
						flag = false if !data.empty?
					end
					return flag
				end

		end
end