module Navi
    class ObjectAccess
				@@epsilon = 0.04
				@@score_ing = 0.75
				@@score_seasoning = 0.95
				@@completion_thresh = 0.875 # (1+@@score_ing)/2
				@@completion_thresh2 = 0.75
				@@sym = :ObjectAccess

        def initialize(app)
            @app = app
				end
		
##########################
# ObjectAccess External Input
##########################
				def route(session_data,ex_input)
					STDERR.puts __LINE__

					session_data[:progress][@@sym],change = self.init(session_data)
					STDERR.puts __LINE__
					update(session_data)
					STDERR.puts __LINE__
				
					case ex_input[:action][:name]
						when 'touch'
							return self.touch(session_data,ex_input,change)
						when 'taken'
							return self.touch(session_data,ex_input,change)
						when 'release'
							return self.release(session_data,ex_input,change)
						when 'put'
							return self.release(session_data,ex_input,change)
						else
							log_error "Unknown action for ObjectAccess algorithm: '#{ex_input[:action][:name]}' is directed by external input."
					end						
				end
				

############################
# ObjectAccess Initialize State
############################

				def init(session_data)
						recipe = session_data[:recipe]
						change = Recipe::StateChange.new
						unless false and session_data[:progress].include?(@@sym) then
							oa_data = Hash.new
							oa_data[:ss_ready] = [] # narrow context
							oa_data[:ss_targets] = [] # wide context
							oa_data[:ss_done] = []
							oa_data[:objects_in_hand] = []
							oa_data[:score] = -100
							
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
							change[@@sym] = oa_data
						else
							STDERR.puts __LINE__
							STDERR.puts session_data[:progress].keys.join(" ")
							oa_data = session_data[:progress][@@sym]
						end

						STDERR.puts __LINE__
							
						# triggers
						temp = recipe.xpath("//substep/trigger").to_a
						STDERR.puts __LINE__
						STDERR.puts oa_data.keys.join(" ")
						all_objects = oa_data[:objects].values.flatten.map{|v|v.to_s}
						STDERR.puts __LINE__

						triggers = temp.delete_if{|v|
								objs = v['ref'].split(/\s+/)
								!objs.subset_of?(all_objects)
						}
						STDERR.puts __LINE__

												
						oa_data[:triggers] = triggers
						return oa_data,change
				end
						
############################
# Touch/Release process
############################

				def touch(session_data,ex_input,change)
					STDERR.puts "touch!"
					oa_data = session_data[:progress][@@sym]
					new_object = ex_input[:action][:target]
					timestamp = ex_input[:action][:timestamp]

					STDERR.puts __LINE__
					#					return do_nothing if oa_data[:objects_in_hand].include?(new_object)


					oa_data[:objects_in_hand] << new_object
					oa_data[:objects_in_hand].uniq!
					
					STDERR.puts __LINE__

					# save backup 
					backup = session_data[:progress].deep_dup
					STDERR.puts __LINE__
					STDERR.puts backup.keys.join(" ")
					STDERR.puts backup[@@sym].keys.join(" ")

					backup[@@sym][:backup] = nil # avoid duplicate backup.
					
					prev_score = oa_data[:score]
					STDERR.puts __LINE__

					state, temp = post_process(session_data,oa_data,timestamp)
					change.deep_merge!(temp)
					STDERR.puts __LINE__
					change[@@sym] = ActiveSupport::HashWithIndifferentAccess.new
					change[@@sym][:backup] = ActiveSupport::HashWithIndifferentAccess.new
					change[@@sym][:backup][new_object] = backup
					change[@@sym][:timestamp] = timestamp if oa_data[:timestamp]==timestamp
					change[@@sym][:score] = oa_data[:score] unless oa_data[:score]==prev_score 
					change[@@sym][:objects_in_hand] = oa_data[:objects_in_hand]
					STDERR.puts change[@@sym]
					return state,change
				end
				
				def release(session_data,ex_input,change)
					STDERR.puts "release!"
					oa_data = session_data[:progress][@@sym]
					gone_object = ex_input[:action][:target]
					timestamp = ex_input[:action][:timestamp]

#					log_error "WARNING: #{gone_object} is not in the list of 'objects in hand.'" unless oa_data[:objects_in_hand].include?(gone_object)
					oa_data[:objects_in_hand].delete(gone_object)
					STDERR.puts __LINE__
					
					# 終了判定をする
					complete = checkCompletion(oa_data,timestamp)
					STDERR.puts __LINE__

					unless complete then
						STDERR.puts __LINE__
						# complete == nil, then turn back to the previous state.
						STDERR.puts session_data[:progress][@@sym].keys.join(" ")
						STDERR.puts session_data[:progress][@@sym][:backup].keys.join(" ")
						change.deep_merge!(session_data[:progress][@@sym][:backup][gone_object.to_sym])
						STDERR.puts __LINE__
						STDERR.puts change
						return "success",change
					else
						prev_score = oa_data[:score]
						state, temp = post_process(session_data,oa_data,timestamp,complete)
						change.deep_merge!(temp)
					end
					change[@@sym] = ActiveSupport::HashWithIndifferentAccess.new
					change[@@sym][:timestamp] = timestamp if oa_data[:timestamp]==timestamp
					change[@@sym][:score] = oa_data[:score] unless oa_data[:score]==prev_score 
					change[@@sym][:objects_in_hand] = oa_data[:objects_in_hand]
					STDERR.puts change[@@sym]

					return state,change
				end

				def checkCompletion(oa_data,timestamp)					
					#					log_error "ERROR: unexpected timestamp at #{__LINE__}" if !oa_data[:timestamp] or oa_data[:timestamp].empty?
					if oa_data.include?(:timestamp) then
						time_diff = Time.parse_my_timestamp(timestamp) - Time.parse_my_timestamp(oa_data[:timestamp])
						# if elapsed time is too short, return nil
						return nil if 1.0 > time_diff
					end				
					return true if oa_data[:score] > @@completion_thresh
					return false
				end
						
				def do_nothing
					return "success", Recipe::StateChange.new
				end
				
				def post_process(session_data,oa_data,timestamp,complete=false)
						STDERR.puts "post_process!"
						ss_current = nil
						progress = session_data[:progress]
						recipe = session_data[:recipe]
						STDERR.puts __LINE__
						max_score, ss_highest_score = argmax_score(oa_data,:ss_forward,recipe, progress)
						STDERR.puts __LINE__
						if max_score >= 1.0 then
							ss_current = ss_highest_score
						else
							max_score2, ss_highest_score2 = argmax_score(oa_data,:ss_backward,recipe,progress)
							if max_score2 >= 1.0 then
								max_score = max_score2
								ss_current = ss_highest_score2								
							elsif max_score >0 then
								ss_current = ss_highest_score
								
								if oa_data[:score] > @@completion_thresh2 then
									# もし，ss_currentがrecommendationと同じものであれば
									# completeをtrueにする
									complete = true if @app.current_substep(recipe,session_data[:progress][:state]).is_next?(ss_current)
								end
							end
						end
						STDERR.puts __LINE__


						# 変化がないなら過去最大のscoreを残す 
						oa_data[:score] = [oa_data[:score], max_score].max

#						return do_nothing if ss_highest_score == @app.current_substep(recipe,session_data[:progress][:state]).id


						return do_nothing(oa_data) if !(!!ss_current or complete)
						STDERR.puts __LINE__
						# 変化あり
						oa_data[:timestamp] = timestamp
						oa_data[:score] = max_score
						
						if ss_current then
							# 指定されたss_currentへ移動
							ex_input = {:navigator=>'default',:action=>{:name=>'jump',:target=>ss_current.to_s,:check=>complete.to_s}}
						else
							# 手がかり無し⇢next関数により推薦された次の作業へ移動
							ex_input = {:navigator=>'default',:action=>{:name=>'next'}}
						end
						return @app.navi_algorithms['default'].route(session_data,ex_input)
				end
								
				def argmax_score(oa_data, target,recipe,progress)
#						STDERR.puts "argmax_score"

						target_substeps = oa_data[target]
						obj_h = oa_data[:objects_in_hand]
						max = -100
						argmax = []

						# when no substep has been done, argmax must be empty.
						STDERR.puts __LINE__
						return max,argmax if target_substeps.empty?
						STDERR.puts __LINE__
					
						for trig in oa_data[:triggers] do
								STDERR.puts __LINE__
								STDERR.puts trig

								STDERR.puts __LINE__
								STDERR.puts trig.parent
								STDERR.puts target_substeps.include?(trig.parent.id)

								next unless target_substeps.include?(trig.parent.id)
								STDERR.puts __LINE__

								score = calc_score(obj_h,trig['ref'].split(/\s+/),oa_data[:objects])
								STDERR.puts "#{score} for #{obj_h.join(" ")} (#{trig.parent.id})"
								next if score < max
								# score==maxなら追加，そうでなければ綺麗に更新
								argmax = [] if score > max
								max = score
								argmax << trig.parent
						end
						STDERR.puts argmax.map{|v|v.id}.join(" ")
						
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
						ss_done = extractCompletedSubsteps(recipe,progress)

						session_data[:progress][@@sym][:ss_done] = ss_done


						ssready = getSSinReady(recipe,progress,ss_done)
						session_data[:progress][@@sym][:ss_ready] = ssready
						session_data[:progress][@@sym][:ss_forward],session_data[:progress][@@sym][:ss_backward] = expandContext(recipe,progress,ssready)
				end
				
				def extractCompletedSubsteps(recipe,progress)
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