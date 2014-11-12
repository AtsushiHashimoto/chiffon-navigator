module Navi
    class ObjectAccess
				@@epsilon = 0.04
				@@score_ing = 0.75
				@@score_seasoning = 0.95
				@@sym = :ObjectAccess

        def initialize(app)
            @app = app
				end
		
##########################
# ObjectAccess External Input
##########################
				def route(session_data,ex_input)
					unless session_data.include?(@@sym) then
							session_data[@@sym] = self.init(session_data[:recipe])
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

				def init(recipe)
						oa_data = Hash.new
						oa_data[:ss_ready] = [] # narrow context
						oa_data[:ss_targets] = [] # wide context
						oa_data[:ss_done] = []
						oa_data[:objects_in_hand] = []
						oa_data[:timestamp] = ""
						
						# ingredient, seasonings, others(=tools)
						objects = Hash.new
						objects[:ingredients] = []
						objects[:seasonings] = []
					
						materials = recipe.xpath("//object").to_a
						for mat in materials do
								next unless mat.attributes.include?('id')
								obj_id, suffix = mat['id'].split('_')
								if suffix=='seasoning' then
										objects[:seasonings] << mat['id']
								else
										objects[:ingredients] << mat['id']
								end
						end
						
						steps = recipe.xpath("//step").to_a
						objects[:mixture] = []
						for step in steps do
								next unless step.attributes.include?('id')
								objects[:mixture] << step.id.to_s
						end
						
						objects[:utensils] = []
						events = recipe.xpath("//event").to_a
						for event in events do
								obj_id, suffix = event['id'].split('_')
								if suffix=='utensil' then
									objects[:utensils] << event['id']
								end
						end
						oa_data[:objects] = objects
						
						# triggers
						temp = recipe.xpath("//substep/trigger").to_a
						
						all_objects = objects.values.flatten.map{|v|v.to_s}
						
						triggers = temp.delete_if{|v|
								objs = v['ref'].split(/\s+/)
								!objs.subset_of?(all_objects)
						}
												
						oa_data[:triggers] = triggers
						return oa_data
				end
						
############################
# Touch/Release process
############################

				def touch(session_data,ex_input)
					STDERR.puts "touch!"
					oa_data = session_data[@@sym]
					new_object = ex_input[:action][:target]


					return do_nothing if oa_data[:objects_in_hand].include?(new_object)
					oa_data[:objects_in_hand] << new_object
					state, change = post_process(session_data,oa_data)
					change[@@sym] = ActiveSupport::HashWithIndifferentAccess.new
					change[@@sym][:objects_in_hand] = oa_data[:objects_in_hand]
					return state,change
				end
				
				def release(session_data,ex_input)
					STDERR.puts "release!"
					oa_data = session_data[@@sym]
					gone_object = ex_input[:action][:target]
					return do_nothing unless oa_data[:objects_in_hand].include?(gone_object)
					STDERR.puts __LINE__
					oa_data[:objects_in_hand].delete(gone_object)
					STDERR.puts __LINE__
					
					# 終了判定をする
					complete = true
					
					state, change = post_process(session_data,oa_data,complete)
					change[@@sym] = ActiveSupport::HashWithIndifferentAccess.new
					change[@@sym][:objects_in_hand] = oa_data[:objects_in_hand]
					return state,change
				end

				def do_nothing
					return "success", Recipe::StateChange.new
				end
				
				def post_process(session_data,oa_data,complete=false)
						STDERR.puts "post_process!"
						ss_current = nil
						progress = session_data[:progress]
						recipe = session_data[:recipe]

						max_score, ss_highest_score = argmax_score(oa_data,:ss_forward,recipe, progress)
						if max_score >= 1.0 then
								ss_current = ss_highest_score
						else
							max_score2, ss_highest_score2 = argmax_score(oa_data,:ss_backward,recipe,progress)
							if max_score2 >= 1.0 then
								ss_current = ss_highest_score2								
							elsif max_score >0 then
								ss_current = ss_highest_score						
							end
						end
						
						return do_nothing if ss_highest_score == @app.current_substep(recipe,session_data[:progress][:state]).id
						STDERR.puts __LINE__
						
						if ss_current then
							STDERR.puts __LINE__
							ex_input = {:navigator=>'default',:action=>{:name=>'jump',:target=>ss_current.to_s}}
							return @app.navi_algorithms['default'].route(session_data,ex_input)
						else
							STDERR.puts __LINE__
							# 手がかり無し
							if complete then
								ex_input = {:navigator=>'default',:action=>{:name=>'next'}}
								return @app.navi_algorithms['default'].route(session_data,ex_input)
							end
							return do_nothing
						end
				end
				
				def argmax_score(oa_data, target,recipe,progress)
						target_substeps = oa_data[target]
						obj_h = oa_data[:objects_in_hand]
						max = -100
						argmax = []
						for trig in oa_data[:triggers] do
								next unless target_substeps.include?(trig.parent.id)
								score = calc_score(obj_h,trig['ref'].split(/\s+/),oa_data[:objects])
#								STDERR.puts "#{score} for #{obj_h.join(" ")} (#{trig.parent.id})"
								next if score < max
								# score==maxなら追加，そうでなければ綺麗に更新
								argmax = [] if score > max
								max = score
								argmax << trig.parent
						end
						
						log_error "ERROR: maybe, there are no triggers?" if argmax.empty?
						if argmax.size > 1 then
							rorder = progress[:recommended_order]
							default_order = recipe.max_order
							argmax.sort!{|a,b|
									a_step_id = a.parent.id.to_s
									b_step_id = b.parent.id.to_s
									result = false
									if a_step_id == b_step_id then
											result = a.order(default_order) <=> b.order(default_order)
									else
											result = rorder.index(a_step_id) <=> rorder.index(b_step_id)
									end
									result
							}

							argmax.reverse! if target == :ss_backward
						end
					
						return max, argmax[0].id
				end
						
				def calc_score(obj_h, obj_v, objects)
						extra_obj = obj_h - obj_v
						ing_v = obj_v & (objects[:ingredients]|objects[:mixture])
						sea_v = obj_v & objects[:seasonings]
						ute_v = obj_v & objects[:utensils]


						# 井上くんのheuristicが変われば設計変更が必要
						has_ing = (ing_v & obj_h).empty? ? 0:1
						has_sea = (sea_v & obj_h).empty? ? 0:1
						has_ute = ute_v & obj_h

						score = 0
						if ute_v.empty? then
								score = score + 1.0 * has_ing
								score = score + @@score_seasoning * has_sea
						else
								score = score + @@score_ing * has_ing
								score = score + (1.0-@@score_ing) * (has_ute.size.to_f/ute_v.size.to_f)
						end

						score - extra_obj.size * @@epsilon
				end

############################
# Context Maintenance Funcs.
############################
				def update(session_data)
						recipe = session_data[:recipe]
						progress = session_data[:progress]
						ss_done = checkCompletion(recipe,progress)

						session_data[@@sym][:ss_done] = ss_done


						ssready = getSSinReady(recipe,progress,ss_done)
						session_data[@@sym][:ss_ready] = ssready
						session_data[@@sym][:ss_forward],session_data[@@sym][:ss_backward] = expandContext(recipe,progress,ssready)
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