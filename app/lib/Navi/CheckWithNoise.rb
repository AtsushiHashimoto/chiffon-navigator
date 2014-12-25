require 'net/http'

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
					
					if ex_input[:action].include?(:value) and ex_input[:action][:value]==false then
						return state, change
					end
					
					#STDERR.puts cwn_data
					#STDERR.puts cwn_data[:noise_reserve]
					#STDERR.puts cwn_data[:noise_reserve][substep_id.to_s]
					
					return state, change if is_empty_noise(cwn_data[:noise_reserve][substep_id])

					# add noise
					recipe = session_data[:recipe]
					ref_progress = session_data[:progress]


					noise_pat = cwn_data[:noise_reserve][substep_id]
					#STDERR.puts noise_pat
					#STDERR.puts noise_pat['slip']
					if noise_pat.include?('slip') and noise_pat['slip'] != :clear then
						false_target = choose_false_target(ref_progress, recipe, noise_pat['slip'][:direction], substep_id)

						ex_input['action'] = {'name'=>'jump','target'=>false_target,'check'=>'true'}
						puts ex_input
						state, temp = @app.navi_algorithms['default'].jump(session_data,ex_input)
						change.deep_merge!(temp)
					end
					
					if noise_pat.include?('jump') and noise_pat['jump']  != :clear then
						false_target = choose_false_target(ref_progress, recipe, noise_pat['jump'][:direction], substep_id)
						
						ex_input['navigator'] = 'default'
						ex_input['action'] = {'name'=>'jump','target'=>false_target,'check'=>'true'}
						delay = noise_pat['jump']['delay'].to_f
						#STDERR.puts ex_input
						#STDERR.puts delay
						
						Process.fork{
							sleep delay
							url = URI.parse(URI.encode("#{@app.settings.viewer_url}/receiver?sessionid=#{session_data[:id]}&string=#{ex_input.to_json}"))
							#STDERR.puts url
							Net::HTTP.get_print url
						}
					end

					
					return state,change
				end
				
				def set_param(session_data,ex_input,change)

					substep_id = ex_input[:action][:target]
					noise_reserve = session_data[:progress][@@sym][:noise_reserve][substep_id]
					unless noise_reserve then
						noise_reserve = {}
					end
					noise = ex_input[:action][:noise]
					noise_type = noise[:type]
					
					
					#STDERR.puts noise
					if noise.include?(:direction) then
						noise_reserve[noise_type] = {:direction=>noise[:direction]}
						
						
						if noise_type == 'jump' then
							noise_reserve[noise_type][:delay] = noise[:delay].to_f					
						end
						change[@@sym][:noise_reserve][substep_id] = noise_reserve
						
					else
						cwn_data = session_data[:progress][@@sym]
						STDERR.puts "clear"
						if cwn_data[:noise_reserve].include?(substep_id) and cwn_data[:noise_reserve][substep_id].include?(noise_type) then
							change[@@sym][:noise_reserve][substep_id] = {} unless change[@@sym][:noise_reserve].include?(substep_id)
							change[@@sym][:noise_reserve][substep_id][noise_type] = :clear 		
						end
					end
					return "sucess", change 
				end
				
				
				def choose_false_target(ref_progress, recipe, direction, right_tar)
					ref_states = ref_progress[:state]
					substeps = recipe.xpath('//substep')
					cands = []
					for ss in substeps do
						next if ss.id == right_tar.to_sym
						next if direction!='able' and ref_states[ss.id][:visual] == :ABLE
						next if direction=='able' and ref_states[ss.id][:visual] != :ABLE

						case direction
							when 'forward' then
								next if ref_states[ss.id][:visual] == :ABLE
								cands << ss.id unless ref_states[ss.id][:is_finished]
							when 'backward' then
								next if ref_states[ss.id][:visual] == :ABLE
								cands << ss.id if ref_states[ss.id][:is_finished]
							when 'not_able' then
								next if ref_states[ss.id][:visual] == :ABLE
								cands << ss.id
							when 'able' then
								next if ref_states[ss.id][:visual] != :ABLE
								cands << ss.id 
							when 'anywhere' then
								cands << ss.id
							else
								log_error("unknown direction '#{direction}' is set to external input.")
						end
					end
					res = cands.sample
					STDERR.puts "SELECTED: #{res}"
					if !res then
						case direction
							when 'forward' then
								res = choose_false_target(ref_progress, recipe, 'able', right_tar)
							when 'backward' then
								res = right_tar
							when 'not_able' then
								res = choose_false_target(ref_progress, recipe, 'able', right_tar)
							when 'able' then
								res = right_tar
							when 'anywhere' then
								log_error("no substeps without '#{right_tar}'?")
							else
							log_error("unknown direction '#{direction}' is set to external input.")
						end												
					end
					return res
				end
				
				def is_empty_noise(noise)
					return true unless noise
					return true if noise.empty?
					flag = true
					for noise_type, data in noise do
						flag = false if !data.empty?
					end
					return flag
				end

		end
end