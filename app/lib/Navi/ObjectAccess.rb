module Navi
    class ObjectAccess
        def initialize(app)
            @app = app
				end
		
##########################
# ObjectAccess External Input
##########################
				def route(session_data,ex_input)
					sym = :ObjectAccess

					unless session_data.include?(sym) then
							session_data[sym] = self.init
					end

					update(session_data)
				
					case ex_input[:action][:name]
						when 'touch'
							return self.touch(session_data,ex_input)
						when 'taken'
							return self.touch(session_data,ex_input)
						when 'release'
							return self.release(session_data,ex_input)
						when 'put'
							return self.release(session_data,ex_input)
						else
							log_error "Unknown action for ObjectAccess algorithm: '#{ex_input[:action][:name]}' is directed by external input."
					end						
				end
				

############################
# ObjectAccess Initialize State
############################

				def init
						oa_data = Hash.new
						oa_data[:ss_ready] = [] # narrow context
						oa_data[:ss_targets] = [] # wide context
						oa_data[:ss_done] = []
						oa_data[:object_in_hand] = []
						oa_data[:timestamp] = ""
						return oa_data
				end

############################
# Touch/Release process
############################

				def touch(session_data,ex_input)
					oa_data = session_data[@sym]
					new_object = ex_input[:action][:target]
					return do_nothing if oa_data[:object_in_hand].include?(new_object)
					oa_data[:object_in_hand] << new_object
					
					return post_process(session_data,oa_data)
				end
				
				def release(session_data,ex_input)
					oa_data = session_data[@sym]
					gone_object = ex_input[:action][:target]
					return do_nothing unless oa_data[:object_in_hand].include?(gone_object)
					oa_data[:object_in_hand].delete(gone_object)
					
					# 終了判定をする
					
					
					return post_process(session_data,oa_data)
				end

				def do_nothing
					return "success", Recipe::StateChange.new
				end
				
				def post_process(session_data,oa_data)
						ss_highest_score = argmax_score(oa_data)
						return do_nothing if ss_highest_score == @app.current_substep(recipe,session_data[:progress][:state])
						ex_input = {:navigator=>'default',:action=>{:name=>'jump',:target=>ss_highest_score.id.to_s}}
						return @app.navi_algorithms['default'].route(session_data,ex_input)
				end
				
				def argmax_score(oa_data)
						
				end

############################
# Context Maintenance Funcs.
############################
				def update(session_data)
						sym = :ObjectAccess

						recipe = session_data[:recipe]
						progress = session_data[:progress]
						ss_done = checkCompletion(recipe,progress)

						session_data[sym][:ss_done] = ss_done


						ssready = getSSinReady(recipe,progress,ss_done)
						session_data[sym][:ss_ready] = ssready
						session_data[sym][:ss_forward],session_data[sym][:ss_backward] = expandContext(recipe,progress,ssready)
				end
				
				def checkCompletion(recipe,progress)
						array = []
						for id,state in progress[:state] do
								# skip states of step nodes (only check substeps)
								next if recipe.getByID(id,"step")
								array << id if state[:is_finished]
						end
						array
				end
		

				# 実行の条件が揃っているsubstepを列挙する
				def getSSinReady(recipe,progress,ss_done)
						steps = recipe.xpath('//step').to_a.find_all{|v|
								!v.attributes.include?('parent') or v['parent'].empty?
						}
						for ss_id in ss_done do
							steps << recipe.getByID(ss_id).parent
						end
						# add steps without parent
						
						steps.uniq!
						
						array = []
						for step in steps do
								temp = findUnfinishedSubsteps(recipe,progress,step.id)
								if temp.empty? then
									# all substeps in the same step has been done
									next unless step.attributes.include?('child')
									child_steps = step['child'].split(/\s+/)
									for child_id in child_steps do
										next unless checkStepReady(recipe,progress,child_id)
										temp += findUnfinishedSubsteps(recipe,progress,child_id)
									end
									end	
								array += temp
						end
						array.uniq
				end
						
				def checkStepReady(recipe,progress,step_id)
						log_error "Unexpected Error" if progress[:state][step_id][:is_finished]
						parents = recipe.getByID(step_id)['parent'].split(/\s+/)
						for parent in parents do
							return false unless progress[:state][parent][:is_finished]
						end	
						true
				end

				def findUnfinishedSubsteps(recipe,progress,step_id,skip_ss=nil)
						default_order = recipe.max_order
						step = recipe.getByID(step_id,'step')

						substeps = step.to_sub.sort_by!{|v| v.order(default_order)}
						array = []
						unfinished_order = default_order
						for ss in substeps do
							next if progress[:state][ss.id][:is_finished]
							next if skip_ss and ss.id == skip_ss.to_sym
							break if unfinished_order < ss.order(default_order)
							array << ss.id
							
							unfinished_order = ss.order
						end
						return array
				end
						
				# 井上アルゴリズムに従ったコンテキストの拡張
				def expandContext(recipe,progress,ssready)

						# forward expansion
						ss_forward = ssready.deep_dup
						for ss_id in ssready do
								step = recipe.getByID(ss_id).parent
								temp = findUnfinishedSubsteps(recipe,progress,step.id,ss_id)
								if temp.empty? then
										next unless step.attributes.include?('child')
										for child_id in step['child'].split(/\s+/) do
												next if checkStepReady(recipe,progress,child_id)
												temp += findUnfinishedSubsteps(recipe,progress,child_id)
										end
								end
								ss_forward += temp
						end
						
#						STDERR.puts "ss_forward: #{ss_forward.join(' ')}"
						
						# backward expansion
						tar_steps = []
						for ss_id in ssready do
								step = recipe.getByID(ss_id).parent
								tar_steps << step
								next unless step.attributes.include?('parent')
								parents = step['parent'].split(/\s+/)
								for p in parents do
									tar_steps << recipe.getByID(p,'step')
								end
						end
						tar_steps.uniq!
						

						ss_backward = []
						for step in tar_steps do
							ss_backward += extractFinishedSS(progress,step)
						end
#						STDERR.puts "ss_backward: #{ss_backward.join(' ')}"

						return ss_forward, ss_backward
				end
						
				def extractFinishedSS(progress,step)
					temp = []
					for ss in step.to_sub do
						temp << ss.id if progress[:state][ss.id][:is_finished]
					end
					temp
				end
				
		end
end