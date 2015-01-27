module Navi
	class ObjectAccess
		@@epsilon = 0.04
		@@score_ing = 0.75
		@@score_seasoning = 0.95
		@@completion_thresh = 0.875 # (1+@@score_ing)/2
		@@completion_thresh2 = 0.75
		@@shortest_touch = 1.0

		@@explicitly = 'explicitly'
		@@probably = 'probably'
		@@sym = :ObjectAccess

		def initialize(app)
			@app = app
		end
		def log_error(str)
			raise str
		end

		@prev_time
		def print_time(line_num)
=begin
			@prev_time = Time.now unless @prev_time
			t = Time.now
			STDERR.puts ""
			STDERR.puts "#{__FILE__} at line #{line_num}: #{t-@prev_time}sec."
			STDERR.puts ""
			@prev_time = t
=end
		end


##########################
# ObjectAccess External Input
##########################
		def route(session_data,ex_input)
			session_data[:progress][@@sym],change = self.init(session_data)
			update(session_data)


			case ex_input[:action][:name]
				when 'touch'
					return self.touch(session_data,ex_input,change)
				when 'taken'
					return self.touch(session_data,ex_input,change)
				when 'release'
					return self.release(session_data,ex_input,change)
				when 'put'
					return self.release(session_data,ex_input,change)
				when 'auto_detection'
					return self.auto_detect(session_data,ex_input,change)
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


			if session_data[:progress][@@sym] == nil then
				print_time(__LINE__)
				oa_data = ActiveSupport::HashWithIndifferentAccess.new
				oa_data[:ss_ready] = [] # narrow context
				oa_data[:ss_targets] = [] # wide context
				oa_data[:ss_done] = []
				oa_data[:objects_in_hand] = []
				oa_data[:score] = -100

				oa_data[:backup] = ActiveSupport::HashWithIndifferentAccess.new
				oa_data[:played_media] = []


				# ingredient, seasonings, others(=tools)
				objects = Hash.new
				objects[:ingredients] = []
				objects[:seasonings] = []

				# 材料表の要素のIDが /.+_seasoning/ だったら調味料, それ以外は食材
				materials = recipe.xpath("//object").to_a
				print_time(__LINE__)
				for mat in materials do
					next unless mat.attributes.include?('id')
					obj_id, suffix = mat['id'].split('_')
					if suffix=='seasoning' then
						objects[:seasonings] << mat['id']
					else
						objects[:ingredients] << mat['id']
					end
				end
				print_time(__LINE__)

				steps = recipe.xpath("//step").to_a
				objects[:mixture] = []
				print_time(__LINE__)
				for step in steps do
					next unless step.attributes.include?('id')
					objects[:mixture] << step.id.to_s
				end
				print_time(__LINE__)

				objects[:utensils] = []
				# <event>のうち，IDが /.+_utensil/ なら道具
				events = recipe.xpath("//event").to_a
				print_time(__LINE__)
				for event in events do
					obj_id, suffix = event['id'].split('_')
					if suffix=='utensil' then
						objects[:utensils] << event['id']
					end
				end
				print_time(__LINE__)
				oa_data[:objects] = objects.deep_dup
				change[@@sym] = oa_data.deep_dup
			else
				oa_data = session_data[:progress][@@sym]
				change[@@sym] = ActiveSupport::HashWithIndifferentAccess.new
				change[@@sym][:backup] = ActiveSupport::HashWithIndifferentAccess.new
			end


			# triggers
			temp = recipe.xpath("//substep/trigger").to_a
			all_objects = oa_data[:objects].values.flatten.map{|v|v.to_s}


			triggers = temp.delete_if{|v|
				objs = v['ref'].split(/\s+/)
				!objs.subset_of?(all_objects)
			}
			trigger_array = []
			for trig in triggers do
				ss = trig.parent.id
				ref = trig['ref'].split(/\s+/)
				trigger_array << [ss,ref]
				#STDERR.puts "#{ss}: #{ref.join(",")}"
			end

			oa_data[:triggers] = trigger_array

			return oa_data,change
		end

############################
# Touch/Release process
############################

		def touch(session_data,ex_input,change, do_backup=true)
			print_time(__LINE__)
			STDERR.puts "touch!"
			oa_data = session_data[:progress][@@sym]
			new_object = ex_input[:action][:target]
			timestamp = ex_input[:action][:timestamp]

#return do_nothing if oa_data[:objects_in_hand].include?(new_object)


			oa_data[:objects_in_hand] << new_object
			oa_data[:objects_in_hand].uniq!


			if do_backup then
				# save backup
				iter_index = session_data[:progress][:iter_index]
				change[@@sym][:backup][iter_index.to_s] = {:timestamp=>timestamp, :touched=>[new_object]}
				#STDERR.puts change[@@sym][:backup][iter_index.to_s]
			end

			prev_score = oa_data[:score]
			state, temp = post_process(session_data,oa_data,timestamp,:touch, false)
			change.deep_merge!(temp)

			c_ss = @app.current_substep(session_data[:recipe],change[:state])
			c_ss = @app.current_substep(session_data[:recipe],session_data[:progress][:state]) unless c_ss
			temp = play_media(c_ss.id.to_s,session_data,oa_data)
			if temp then
				STDERR.puts temp
				change.deep_merge!(temp)
			end
			change[@@sym][:played_media] = oa_data[:played_media]


			change[@@sym][:timestamp] = timestamp if oa_data[:timestamp]==timestamp
			change[@@sym][:score] = oa_data[:score] unless oa_data[:score]==prev_score
			change[@@sym][:objects_in_hand] = oa_data[:objects_in_hand]
			#	STDERR.puts change[@@sym]
			print_time(__LINE__)
			return state,change
		end

		def release(session_data,ex_input,change, do_backup=true)
			print_time(__LINE__)
			STDERR.puts "release!"
			oa_data = session_data[:progress][@@sym]
			gone_object = ex_input[:action][:target]
			timestamp = ex_input[:action][:timestamp]

#					@app.log_error("WARNING: #{gone_object} is not in the list of 'objects in hand.'") unless oa_data[:objects_in_hand].include?(gone_object)
			oa_data[:objects_in_hand].delete(gone_object)


# 把持の正当性判定を行う(1秒以内に解放→把持と見なさない
			touched_iter_index = isTouchValid?(gone_object,timestamp, oa_data[:backup])
			if touched_iter_index then
				return recalculation(session_data, touched_iter_index, gone_object)
			end

# 終了判定

			is_completed, changed_iter_index = check_completion(oa_data, gone_object,timestamp)
			unless nil == changed_iter_index then
				return @app.settings.navi_algorithms['default'].prev(session_data,changed_iter_index-1)
			end
			if do_backup then
				iter_index = session_data[:progress][:iter_index]
				change[@@sym][:backup][iter_index.to_s] = {:timestamp=>timestamp, :released=>[gone_object]}
				#STDERR.puts change[@@sym][:backup][iter_index.to_s]
			end

			prev_score = oa_data[:score]
			state, temp, ss_current = post_process(session_data,oa_data,timestamp,:release, is_completed)
			change.deep_merge!(temp)

			c_ss = @app.current_substep(session_data[:recipe],change[:state])
			c_ss = @app.current_substep(session_data[:recipe],session_data[:progress][:state]) unless c_ss
			temp = play_media(c_ss.id.to_s,session_data,oa_data,[gone_object])
			if temp then
				STDERR.puts temp
				change.deep_merge!(temp)
			end
			change[@@sym][:played_media] = oa_data[:played_media]

			change[@@sym][:timestamp] = timestamp if oa_data[:timestamp]==timestamp
			change[@@sym][:score] = oa_data[:score] unless oa_data[:score]==prev_score
			change[@@sym][:objects_in_hand] = oa_data[:objects_in_hand]

			print_time(__LINE__)
			return state,change
		end

		def getTimeDiff(ts1,ts2)
			Time.parse_my_timestamp(ts1) - Time.parse_my_timestamp(ts2)
		end

		def isTouchValid?(gone_object,timestamp,backup)
			indices = backup.keys.map{|v|v.to_s.to_i}.sort.reverse
			for iter_index in indices do
				record = backup[iter_index.to_s.to_sym]
				next if nil == record[:touched] or !record[:touched].include?(gone_object)
				time_diff = getTimeDiff(timestamp, record[:timestamp])
				return iter_index if @@shortest_touch > time_diff
				return nil
			end
			return nil
		end

		def recalculation(session_data, touched_iter_index, gone_object)
			STDERR.puts "recalculation"
			oa_data = session_data[:progress][@@sym]

			backup = oa_data[:backup]

			record = backup[touched_iter_index.to_s]
			record[:touched] -= [gone_object]
			# progressのbackupから消えているか確認
			if (nil == record[:touched] or record[:touched].empty?) and (nil == record[:released] or record[:released].empty?) then
				STDERR.puts "delete touch history."
				backup.delete(touched_iter_index.to_s)
				oa_data[:backup] = backup
			end
			history = oa_data[:backup].select{|key,record|key.to_i >= touched_iter_index}

			# 把持の直前の時点まで状態を戻す
			state,change = @app.navi_algorithms['default'].prev(session_data,touched_iter_index-1)
			return state,change
			ref_progress = session_data[:progress].deep_dup
			session_data[:progress] = session_data[:progress].clear_by(change)
			session_data[:progress].deep_merge!(change)

			for key, record in history do
				state, temp = multi_process(session_data,record[:gone_objects],record[:new_objects],record[:timestamp],change, false)
				change.deep_merge!(temp)
			end

			session_data[:progress] = ref_progress
			return state, change
		end

		def do_nothing
			STDERR.puts "do_nothing"
			return "success", Recipe::StateChange.new
		end

		def post_process(session_data,oa_data,timestamp,action,complete)
			STDERR.puts "post_process! (action: #{action})"
			STDERR.puts "COMPLETE!" if complete
			print_time(__LINE__)
#						STDERR.puts action.class
			ss_current = nil
			progress = session_data[:progress]
			recipe = session_data[:recipe]
			max_score, ss_highest_score, fired_trigger = argmax_score(oa_data,:ss_forward,recipe, progress)
			STDERR.puts "max score (forward): #{max_score}"
			if max_score >= 1.0 then
				ss_current = ss_highest_score
			else
				max_score2, ss_highest_score2, fired_trigger = argmax_score(oa_data,:ss_backward,recipe,progress)
				STDERR.puts "max score (backward): #{max_score2}"
				if max_score2 >= 1.0 then
					max_score = max_score2
					ss_current = ss_highest_score2
				elsif action==:touch and max_score >0 then
					ss_current = ss_highest_score

					STDERR.puts oa_data[:score]
					if oa_data[:score] > @@completion_thresh2 then
						# もし，ss_currentがrecommendationと同じものであれば
						# × completeをtrueにする
						# ○ confidenceをexplicitlyにする
						c_ss = @app.current_substep(recipe,session_data[:progress][:state])
						next_ss = c_ss.next_substep(recipe.max_order)

						# log_error("c_ss.next_substepと選択される次のsubstepが一致!!")
						oa_data[:confidence_support] = true	if ss_current == next_ss

						#	complete = true if c_ss.is_next?(ss_current, recipe.max_order)
					end
				end
			end


			# 変化がないなら過去最大のscoreを残す
			#STDERR.puts [max_score,oa_data[:score]].join(" > ")
			if oa_data[:score] <= max_score then
				oa_data[:score] = max_score
				if max_score >= @@completion_thresh then
					oa_data[:confidence] = @@explicitly
				elsif max_score < @@completion_thresh2 then
					oa_data[:confidence] = @@probably
				elsif oa_data[:confidence_support] == true then
					oa_data[:confidence] = @@explicitly
				else
					oa_data[:confidence] = @@probably
				end
				STDERR.puts "confidence: #{oa_data[:confidence]}"
			end

			#if !(!!ss_current or complete)
			if ss_current==nil and !complete then
				return do_nothing
			end

			# 変化あり
			oa_data[:timestamp] = timestamp
			oa_data[:changed_iter_index] = progress[:iter_index]
			oa_data[:confidence_support] = false
			if ss_current != @app.current_substep(recipe,session_data[:progress][:state]).id then
				STDERR.puts "reset played_media: #{oa_data[:played_media].join(', ')}"
				oa_data[:played_media] = []
			end

			# 井上論文に書いてない処理(解放による終了判定で別のものを表示するときは，scoreを0(推薦)とする)
			if action == :release and complete then
				oa_data[:score] = 0
				oa_data[:confidence] = @@probably
				ss_current = nil
			else
				oa_data[:score] = max_score
			end
			oa_data[:related_objects] = fired_trigger[1] if fired_trigger

			ex_input = {:navigator=>'default',:action=>{:name=>'check', :target=>@app.current_substep(recipe,session_data[:progress][:state]).id, :value=>complete}}
			state, change = @app.navi_algorithms['default'].check(session_data,ex_input)

			if ss_current then
				# 指定されたss_currentへ移動
				ex_input = {:navigator=>'default',:action=>{:name=>'jump',:target=>ss_current.to_s,:check=>'false'}}
				states, temp = @app.navi_algorithms['default'].jump(session_data,ex_input)
				change.deep_merge!(temp)
				#else
				## 手がかり無し⇢next関数により推薦された次の作業へ移動
			end
			print_time(__LINE__)

			return state,change
		end

		def argmax_score(oa_data, target,recipe,progress)
			STDERR.puts "argmax_score"

			target_substeps = oa_data[target]
			obj_h = oa_data[:objects_in_hand]
			max = -100
			argmax = []

			# when no substep has been done, argmax must be empty.
			return max,argmax if target_substeps.empty?

			for trig in oa_data[:triggers] do
				next unless target_substeps.include?(trig[0])
				score = calc_score(obj_h,trig[1],oa_data[:objects])
				# STDERR.puts "#{score} for #{obj_h.join(" ")} (#{trig[0]})"
				next if score < max
				# score==maxなら追加，そうでなければ綺麗に更新
				argmax = [] if score > max
				max = score
				argmax << trig
			end


			log_error "ERROR: maybe, there are no triggers?" if argmax.empty?

			if argmax.size > 1 then
				rorder = progress[:recommended_order]
				default_order = recipe.max_order
				argmax.sort!{|a,b|
					a_step_id = recipe.getByID(a[0]).parent.id
					b_step_id = recipe.getByID(b[0]).parent.id
					result = -1
					if a_step_id == b_step_id then
						result = (recipe.getByID(b[0]).order(default_order) <=> recipe.getByID(a[0]).order(default_order))
					else
						result = (rorder.index(b_step_id) <=> rorder.index(a_step_id))
					end
					result
				}

				argmax.reverse! if target == :ss_backward
			end

			return max, argmax[0][0],argmax[0]
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
				score = score + [1.0 * has_ing, @@score_seasoning * has_sea].max
			else
				score = score + (@@score_ing * [has_ing, has_sea].max)

				score = score + (1.0-@@score_ing) * (has_ute.size.to_f/ute_v.size.to_f)
			end
			return score - extra_obj.size * @@epsilon
		end


		def check_completion(oa_data, gone_object, timestamp)
			STDERR.puts "check_completion"
			if oa_data[:related_objects] then
				return false unless oa_data[:related_objects].include?(gone_object)
			end
			return false, oa_data[:changed_iter_index].to_s.to_i if getTimeDiff(timestamp, oa_data[:timestamp]) < @@shortest_touch
			return false if oa_data[:related_objects].size > 1 and oa_data[:objects][:ingredients].include?(gone_object)
			return true if oa_data[:confidence] == @@explicitly

			return false

			#oa_data[:score] > @@completion_thresh
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
			# add steps without parent
			steps = recipe.xpath('//step').to_a.find_all{|v|
				!v.attributes.include?('parent') or v['parent'].empty?
			}
			for ss_id in ss_done do
				steps << recipe.getByID(ss_id).parent
			end

			steps.uniq!

			array = []
			for step in steps do
				temp = findUnfinishedSubsteps(recipe,progress,step.id)
				if temp.empty? then
					# all substeps in the same step has been done
					next unless step.attributes.include?('child')
					child_steps = step['child'].split(/\s+/)
					for child_id in child_steps do
						# STDERR.puts "#{child_id} as the child of #{step.id}"
						next unless checkStepReady(recipe,progress,child_id)
						next if progress[:state][child_id][:is_finished]
						temp += findUnfinishedSubsteps(recipe,progress,child_id)
					end
				end
				array += temp
			end
			array.uniq
		end

		def checkStepReady(recipe,progress,step_id)
			#STDERR.puts step_id
			progress[:state][step_id]

			# 既に終了しているstepならfalse
			return false if progress[:state][step_id][:is_finished]

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

############################
# Both touch and released objects are input at the same time.
# from ObjectAccessFuzzy.
############################

		def auto_detect(session_data,ex_input,change)
			STDERR.puts "auto_detect!"
			gone_objects = ex_input[:action][:released].map{|v|v.to_s}
			new_objects = ex_input[:action][:touched].map{|v|v.to_s}
			timestamp = ex_input[:action][:timestamp]
			return multi_process(session_data, gone_objects,new_objects,timestamp,change)
		end

		def multi_process(session_data,gone_objects,new_objects,timestamp,change, do_backup=true)
			if do_backup then
				iter_index = session_data[:progress][:iter_index]
				change[@@sym][:backup][iter_index.to_s] = {:timestamp=>timestamp, :touched=>new_objects, :released=>[gone_objects]}
				#STDERR.puts change[@@sym][:backup][iter_index.to_s]
			end


			temp_ex_input = {:timestamp=>timestamp, :action=>{}}
			for gone_obj in gone_objects do
				temp_ex_input[:action][:target] = gone_obj
				status, temp = release(session_data,temp_ex_input, change, false)
				change.deep_merge!(temp)
			end
			for new_obj in new_objects do
				temp_ex_input[:action][:target] = gone_obj
				status, temp = touch(session_data,temp_ex_input, change, false)
				change.deep_merge!(temp)
			end
			return status, change
		end

		# 現在表示されていて，確信度がexplicitlyで，かつ，
		# if triggerがない
		#   無条件で
		# else
		# 	triggerにある食材が把持されていたら
		# メディア(audio,video,notification問わず)を再生する．

		# 指定したメディアを再生するような指示を作る
		def play_media(ss_current,session_data,oa_data,released_objects=nil)
			# メディアの再生をチェックする
			change = Recipe::StateChange.new
			return nil unless oa_data[:confidence]==@@explicitly

			recipe = session_data[:recipe]
			progress = session_data[:progress]

			ss = recipe.getByID(ss_current,'substep')

			ss.children.each{|node|
				next unless ['video','audio','notification'].include?(node.name)
				next if oa_data[:played_media].include?(node['id'])

				delay_array = []
				node.xpath('./trigger').each{|trig|
					ref = trig[:ref].split(" ")
					ref.delete('sametime')

					if trig[:timing]=='start' then
						next unless ref.subset_of?(oa_data[:objects_in_hand])
					elsif trig[:timing]=='end' then
						next unless ref.subset_of?(oa_data[:objects_in_hand]+released_objects)
						next if ref.subset_of?(oa_data[:objects_in_hand])
					end
					delay_array << trig[:delay].to_f
				}
				next if delay_array.empty?
				delay = delay_array.min
				change.deep_merge!(@app.play_control(recipe, progress, :PLAY, node['id'],delay)[1])
				oa_data[:played_media] << node['id']
			}
			return change
		end
=begin
					oa_data = session_data[:progress][@@sym]
					gone_objects = ex_input[:action][:released].map{|v|v.to_s}
					new_objects = ex_input[:action][:touched].map{|v|v.to_s}
					timestamp = ex_input[:action][:timestamp]

					oa_data[:objects_in_hand] -= gone_objects
					oa_data[:objects_in_hand] += new_objects
					oa_data[:objects_in_hand].uniq!

					STDERR.puts "+" + new_objects.join("/")
					STDERR.puts "-" + gone_objects.join("/")
					STDERR.puts "=" + oa_data[:objects_in_hand].join(" ")

					# save backup
					backup = session_data[:progress].deep_dup
					if backup[@@sym][:backup] then
						backup[@@sym][:backup] = nil # avoid duplicate backup.
					end

					complete = false
					unless gone_objects.empty? then
						# 終了判定をする
						complete = checkCompletion(oa_data,timestamp)
					end

					STDERR.puts complete

					if nil == complete then
						STDERR.puts __LINE__
						if new_objects.empty? then
							# complete == nil, then turn back to the previous state.
							gone_object = getMostRecentTouched(session_data[:progress],gone_objects)
							if gone_object then
								change.deep_merge!(session_data[:progress][@@sym][:backup][gone_object.to_sym])
								for gone_object in gone_objects do
									change[@@sym][:backup][gone_object.to_sym] = :__clear__
								end
							end
							return "success",change
						end
						# 新しく把持された物体があるなら，それに従って変更する
						complete = false
						STDERR.puts __LINE__
					end

					STDERR.puts __LINE__
					prev_score = oa_data[:score]
					state, temp = post_process(session_data,oa_data,timestamp,complete)
					change.deep_merge!(temp)
					change[@@sym][:backup] = Hash.new unless change[@@sym].include?(:backup)
					for new_object in new_objects do
							change[@@sym][:backup][new_object.to_sym] = backup
					end
					for gone_object in gone_objects do
							change[@@sym][:backup][gone_object.to_sym] = :__clear__
					end
					change[@@sym][:timestamp] = timestamp if oa_data[:timestamp]==timestamp
					change[@@sym][:score] = oa_data[:score] unless oa_data[:score]==prev_score
					change[@@sym][:objects_in_hand] = oa_data[:objects_in_hand]


					return state,change
				end

				# かなり挙動が怪しそう．バグある??
				def getMostRecentTouched(progress,objects)
					oa_data = progress[@@sym]
					time = Time.new
					most_recent_obj = nil
					for obj in objects do
						next unless oa_data[:backup].include?(obj)
						if oa_data[:backup][obj][@@sym].include?(:timestamp) then
							curr_time = Time.parse_my_timestamp(oa_data[:backup][obj][@@sym][:timestamp])
						else
							curr_time = Time.new
						end
						next if curr_time <= time
						time = curr_time
						most_recent_obj = obj
					end
					STDERR.puts "most_recent_obj: #{most_recent_obj}"
					return most_recent_obj
				end
=end

	end
end