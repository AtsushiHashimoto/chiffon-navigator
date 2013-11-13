#!/usr/bin/ruby

require 'rubygems'
require 'json'
require 'nokogiri'

def parse_xml(xmlfile)
	doc = Nokogiri::XML(open(xmlfile))
	hash_recipe = Hash.new{|h,k| h[k]=Hash.new(&h.default_proc)}

	# directions/stepの書き出し
	hash_recipe = get_step(doc, hash_recipe)
	# directions/substepの書き出し
	doc.xpath("//directions/substep").each{|node|
		substep_id = node["id"]
		hash_recipe = get_substep(doc, hash_recipe, nil, substep_id)
	}
	# recipe/notificationの書き出し
	doc.xpath("//recipe/notification").each{|node|
		notification_id = node["id"]
		hash_recipe = get_notification(doc, hash_recipe, nil, notification_id)
	}
	# recipe/materials/objectの書き出し
	doc.xpath("//object").each{|node|
		object_id = node["id"]
		hash_recipe["object"][object_id] = 1
	}
	# recipe/eventの書き出し
	doc.xpath("//recipe/event").each{|node|
		event_id = node["id"]
		hash_recipe["event"][event_id] = 1
	}
	return hash_recipe
end

# step
# hash_recipe["step"][id] : stepのidをキーとする．
# hash_recipe["step"][id]["parent"] = [id1, id2, ...] : stepのparentリスト
# hash_recipe["step"][id]["chain"] = id : stepのchain
# hash_recipe["step"][id]["priority"] = number : stepのpriority．
# hash_recipe["step"][id]["trigger"] = [{"timing": , "ref":{"taken":{"food":[], "seasoning":[], "utensil":[]}, "put":{"food":[], "seasoning":[], "utensil":[]}}, "delay": }, {...}, ...] : stepのtriggerリスト
# hash_recipe["step"][id]["substep"] = [id, id, ...] : stepのsubstepリスト
# hash_recipe["sorted_step"] = [[priproty, id], [...], ...] : stepのpriority順にソートしたstepのidリスト
def get_step(doc, hash_recipe)
	# priorityのソートのために保持
	priority_list = []
	doc.xpath("//recipe/directions/step").each{|node|
		# id
		step_id = node["id"]
		# parent
		hash_recipe["step"][step_id]["parent"] = []
		unless node["parent"] == nil
			node["parent"].split(" ").each{|v|
				hash_recipe["step"][step_id]["parent"].push(v)
			}
		end
		# chain
		hash_recipe["step"][step_id]["chain"] = []
		unless node["chain"] == nil
			hash_recipe["step"][step_id]["chain"].push(node["chain"])
		end
		# priority
		# 基本的にelementの記述順序どおりにpriority_listに代入していく
		# priorityが指定されているときのみ，それに合わせた位置に代入する．
		# 一番初めにpriorityを指定されたstepの位置が基準となるので，最適な順序で並べられているわけではない．
		# chainのつながりも含めてpriorityの順番を決めるべきだが，難しいのでやらない．
		if node["priority"] != nil
			# priorityを持つならば，priority_listの中で自分より小さいものの前に代入する
			# priority_listが全てnilならば，pushする
			priority_num = node["priority"].to_i
			if priority_list.size == 0
				priority_list.push([step_id, priority_num])
			else
				for i in 0..(priority_list.size-1)
					if priority_list[i][1] != nil && priority_num > priority_list[i][1]
						priority_list.insert(i, [step_id, priority_num])
						break
					end
					if i == priority_list.size-1
						priority_list.push([step_id, priority_num])
						break
					end
				end
			end
		else
			# priorityを持たないならば，nilとしてpush代入する
			priority_list.push([step_id,nil])
		end
		# trigger
		hash_recipe["step"][step_id]["trigger"] = []
		unless doc.xpath("//recipe/directions/step[@id=\"#{step_id}\"]/trigger")[0] == nil
			doc.xpath("//recipe/directions/step[@id=\"#{step_id}\"]/trigger").each{|trigger|
				# timing
				timing = nil
				if trigger["timing"] == nil
					timing = "start"
				else
					timing = trigger["timing"]
				end
				# ref
				ref = {"taken"=>{"food"=>[], "seasoning"=>[], "utensil"=>[]}, "put"=>{"food"=>[], "seasoning"=>[], "utensil"=>[]}, "other"=>[]}
				trigger["ref"].split(" ").each{|value|
					if /^taken_.*$/ =~ value
						if /^taken_food_(.*)$/ =~ value
							ref["taken"]["food"].push($1)
						elsif /^taken_seasoning_(.*)$/ =~ value
							ref["taken"]["seasoning"].push($1)
						elsif /^taken_utensil_(.*)$/ =~ value
							ref["taken"]["utensil"].push($1)
						end
					elsif /^put_.*$/ =~ value
						if /^put_food_(.*)$/ =~ value
							ref["put"]["food"].push($1)
						elsif /^put_seasoning_(.*)$/ =~ value
							ref["put"]["seasoning"].push($1)
						elsif /^put_utensil_(.*)$/ =~ value
							ref["put"]["utensil"].push($1)
						end
					else
						ref["other"].push(value)
					end
				}
				# delay
				delay = -1
				if trigger["delay"] == nil
					delay = 0
				else
					delay = trigger["delay"]
				end
				hash_recipe["step"][step_id]["trigger"].push({"timing"=>timing, "ref"=>ref, "delay"=>delay})
			}
		end
		# substep
		hash_recipe["step"][step_id]["substep"] = []
		doc.xpath("//recipe/directions/step[@id=\"#{step_id}\"]/substep").each{|node2|
			# id
			substep_id = node2["id"]
			hash_recipe["step"][step_id]["substep"].push(substep_id)
			hash_recipe = get_substep(doc, hash_recipe, step_id, substep_id)
		}
	}
	# priority_listでの位置に合わせてpriorityの設定
	for i in 0..(priority_list.size-1)
		hash_recipe["step"][priority_list[i][0]]["priority"] = 100 - i
	end
	# stepをpriorityの降順に並べたhash_recipe[sorted_step]を作成
	hash_recipe["sorted_step"] = []
	hash_recipe["step"].each{|key, value|
		hash_recipe["sorted_step"].push([value["priority"], key])
	}
	hash_recipe["sorted_step"].sort!{|v1, v2|
		v2[0] <=> v1[0]
	}

	return hash_recipe
end

# substep
# hash_recipe["substep"][id] : substepのid
# hash_recipe["substep"][id]["parent_step"] = id : parent nodeなstepのid
# hash_recipe["substep"][id]["order"] = order_num : substepのorderの番号
# hash_recipe["substep"][id]["trigger"] = 他のtriggerと同じ形式
# hash_recipe["substep"][id]["notification"] = [id, id, ...] : notificationのidリスト
# hash_recipe["substep"][id]["audio"] = [id] : audioのid．便宜上配列にしている．
# hash_recipe["substep"][id]["video"] = [id] : videoのid．便宜上配列にしている．
# hash_recipe["substep"][id]["prev_substep"] = id : 前のsubstepのid
# hash_recipe["substep"][id]["next_substep"] = id : 次のsubstepのid
def get_substep(doc, hash_recipe, step_id, substep_id)
	hash_recipe["substep"][substep_id]["parent_step"] = nil
	unless step_id == nil
		# directions/step以下に書かれているsubsteはparent_stepを持つ
		hash_recipe["substep"][substep_id]["parent_step"] = step_id
	end
	# order
	hash_recipe["substep"][substep_id]["order"] = nil
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]")[0]["order"] == nil
		hash_recipe["substep"][substep_id]["order"] = doc.xpath("//substep[@id=\"#{substep_id}\"]")[0]["order"]
	end
	# trigger
	hash_recipe["substep"][substep_id]["trigger"] = []
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/trigger")[0] == nil
		doc.xpath("//substep[@id=\"#{substep_id}\"]/trigger").each{|trigger|
			# timing
			timing = nil
			if trigger["timing"] == nil
				timing = "start"
			else
				timing = trigger["timing"]
			end
			# ref
			ref = {"taken"=>{"food"=>[], "seasoning"=>[], "utensil"=>[]}, "put"=>{"food"=>[], "seasoning"=>[], "utensil"=>[]}, "other"=>[]}
			trigger["ref"].split(" ").each{|value|
				if /^taken_.*$/ =~ value
					if /^taken_food_(.*)$/ =~ value
						ref["taken"]["food"].push($1)
					elsif /^taken_seasoning_(.*)$/ =~ value
						ref["taken"]["seasoning"].push($1)
					elsif /^taken_utensil_(.*)$/ =~ value
						ref["taken"]["utensil"].push($1)
					end
				elsif /^put_.*$/ =~ value
					if /^put_food_(.*)$/ =~ value
						ref["put"]["food"].push($1)
					elsif /^put_seasoning_(.*)$/ =~ value
						ref["put"]["seasoning"].push($1)
					elsif /^put_utensil_(.*)$/ =~ value
						ref["put"]["utensil"].push($1)
					end
				else
					ref["other"].push(value)
				end
			}
			# delay
			delay = -1
			if trigger["delay"] == nil
				delay = 0
			else
				delay = trigger["delay"]
			end
			hash_recipe["substep"][substep_id]["trigger"].push({"timing"=>timing, "ref"=>ref, "delay"=>delay})
		}
	end
	# notification
	hash_recipe["substep"][substep_id]["notification"] = []
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/notification")[0] == nil
		doc.xpath("//substep[@id=\"#{substep_id}\"]/notification").each{|node|
			notification_id = node["id"]
			hash_recipe["substep"][substep_id]["notification"].push(notification_id)
			hash_recipe = get_notification(doc, hash_recipe, substep_id, notification_id)
		}
	end
	# audio
	hash_recipe["substep"][substep_id]["audio"] = []
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/audio")[0] == nil
		audio_id = doc.xpath("//substep[@id=\"#{substep_id}\"]/audio")[0]["id"]
		hash_recipe["substep"][substep_id]["audio"].push(audio_id)
		hash_recipe = get_audio(doc, hash_recipe, substep_id, nil, audio_id)
	end
	# video
	hash_recipe["substep"][substep_id]["video"] = []
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/video")[0] == nil
		video_id = doc.xpath("//substep[@id=\"#{substep_id}\"]/video")[0]["id"]
		hash_recipe["substep"][substep_id]["video"].push(video_id)
		hash_recipe = get_video(doc, hash_recipe, substep_id, video_id)
	end
	# 前のsubstep
	hash_recipe["substep"][substep_id]["prev_substep"] = nil
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].previous_sibling == nil
		if doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].previous_sibling.name == "substep"
			prev_substep = doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].previous_sibling["id"]
			hash_recipe["substep"][substep_id]["prev_substep"] = prev_substep
		end
	end
	# 次のsubstep
	hash_recipe["substep"][substep_id]["next_substep"] = nil
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].next_sibling == nil
		if doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].next_sibling.name == "substep"
			next_substep = doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].next_sibling["id"]
			hash_recipe["substep"][substep_id]["next_substep"] = next_substep
		end
	end
	return hash_recipe
end

# notification
# hash_recipe["notification"][id] : notificationのid
# hash_recipe["notification"][id]["parent_substep"] = id : parent nodeなsubstepのid
# hash_recipe["notification"][id]["trigger"] = 他のtriggerと同じ形式
# hash_recipe["notification"][id]["audio"] = [id] : notificationのaudio．便宜上配列にしている．
def get_notification(doc, hash_recipe, substep_id, notification_id)
	hash_recipe["notification"][notification_id]["parent_substep"] = nil
	unless substep_id == nil
		hash_recipe["notification"][notification_id]["parent_substep"] = substep_id
	end
	# triggerの取り出し
	hash_recipe["notification"][notification_id]["trigger"] = []
	unless doc.xpath("//notification[@id=\"#{notification_id}\"]/trigger")[0] == nil
		doc.xpath("//notification[@id=\"#{notification_id}\"]/trigger").each{|trigger|
			# timing
			timing = nil
			if trigger["timing"] == nil
				timing = "start"
			else
				timing = trigger["timing"]
			end
			# ref
			ref = {"taken"=>{"food"=>[], "seasoning"=>[], "utensil"=>[]}, "put"=>{"food"=>[], "seasoning"=>[], "utensil"=>[]}, "other"=>[]}
			trigger["ref"].split(" ").each{|value|
				if /^taken_.*$/ =~ value
					if /^taken_food_(.*)$/ =~ value
						ref["taken"]["food"].push($1)
					elsif /^taken_seasoning_(.*)$/ =~ value
						ref["taken"]["seasoning"].push($1)
					elsif /^taken_utensil_(.*)$/ =~ value
						ref["taken"]["utensil"].push($1)
					end
				elsif /^put_.*$/ =~ value
					if /^put_food_(.*)$/ =~ value
						ref["put"]["food"].push($1)
					elsif /^put_seasoning_(.*)$/ =~ value
						ref["put"]["seasoning"].push($1)
					elsif /^put_utensil_(.*)$/ =~ value
						ref["put"]["utensil"].push($1)
					end
				else
					ref["other"].push(value)
				end
			}
			# delay
			delay = -1
			if trigger["delay"] == nil
				delay = 0
			else
				delay = trigger["delay"]
			end
			hash_recipe["notification"][notification_id]["trigger"].push({"timing"=>timing, "ref"=>ref, "delay"=>delay})
		}
	end
	# audioの取り出し
	hash_recipe["notification"][notification_id]["audio"] = []
	unless doc.xpath("//notification[@id=\"#{notification_id}\"]/audio")[0] == nil
		audio_id = doc.xpath("//notification[@id=\"#{notification_id}\"]/audio")[0]["id"]
		hash_recipe["notification"][notification_id]["audio"].push(audio_id)
		hash_recipe = get_audio(doc, hash_recipe, nil, notification_id, audio_id)
	end
	return hash_recipe
end

# audio
# hash_recipe["audio"][id] : audioのid
# hash_recipe["audio"][id]["parent_substep"] = id : parent nodeなsubstepのid
# hash_recipe["audio"][id]["parent_notification"] = id : parent nodeなnotificationのid
# hash_recipe["audio"][id]["trigger"] = 他のtriggerと同じ形式
def get_audio(doc, hash_recipe, substep_id, notification_id, audio_id)
	hash_recipe["audio"][audio_id]["parent_substep"] = nil
	unless substep_id == nil
		hash_recipe["audio"][audio_id]["parent_substep"] = substep_id
	end
	hash_recipe["audio"][audio_id]["parent_notification"] = nil
	unless notification_id == nil
		hash_recipe["audio"][audio_id]["parent_notification"] = notification_id
	end
	# triggerの取り出し
	hash_recipe["audio"][audio_id]["trigger"] = []
	unless doc.xpath("//audio[@id=\"#{audio_id}\"]/trigger")[0] == nil
		doc.xpath("//audio[@id=\"#{audio_id}\"]/trigger").each{|trigger|
			# timing
			timing = nil
			if trigger["timing"] == nil
				timing = "start"
			else
				timing = trigger["timing"]
			end
			# ref
			ref = {"taken"=>{"food"=>[], "seasoning"=>[], "utensil"=>[]}, "put"=>{"food"=>[], "seasoning"=>[], "utensil"=>[]}, "other"=>[]}
			trigger["ref"].split(" ").each{|value|
				if /^taken_.*$/ =~ value
					if /^taken_food_(.*)$/ =~ value
						ref["taken"]["food"].push($1)
					elsif /^taken_seasoning_(.*)$/ =~ value
						ref["taken"]["seasoning"].push($1)
					elsif /^taken_utensil_(.*)$/ =~ value
						ref["taken"]["utensil"].push($1)
					end
				elsif /^put_.*$/ =~ value
					if /^put_food_(.*)$/ =~ value
						ref["put"]["food"].push($1)
					elsif /^put_seasoning_(.*)$/ =~ value
						ref["put"]["seasoning"].push($1)
					elsif /^put_utensil_(.*)$/ =~ value
						ref["put"]["utensil"].push($1)
					end
				else
					ref["other"].push(value)
				end
			}
			# delay
			delay = -1
			if trigger["delay"] == nil
				delay = 0
			else
				delay = trigger["delay"]
			end
			hash_recipe["audio"][audio_id]["trigger"].push({"timing"=>timing, "ref"=>ref, "delay"=>delay})
		}
	end
	return hash_recipe
end

# video
# hash_recipe["video"][id] : videoのid
# hash_recipe["video"][id]["parent_substep"] = id : parent nodeなsubstepのid
# hash_recipe["video"][id]["trigger"] 他のtriggerと同じ形式
def get_video(doc, hash_recipe, substep_id, video_id)
	hash_recipe["video"][video_id]["parent_substep"] = substep_id
	# triggerの取り出し
	hash_recipe["video"][video_id]["trigger"] = []
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/video[@id=\"#{video_id}\"]/trigger")[0] == nil
		doc.xpath("//substep[@id=\"#{substep_id}\"]/video[@id=\"#{video_id}\"]/trigger").each{|trigger|
			# timing
			timing = nil
			if trigger["timing"] == nil
				timing = "start"
			else
				timing = trigger["timing"]
			end
			# ref
			ref = {"taken"=>{"food"=>[], "seasoning"=>[], "utensil"=>[]}, "put"=>{"food"=>[], "seasoning"=>[], "utensil"=>[]}, "other"=>[]}
			trigger["ref"].split(" ").each{|value|
				if /^taken_.*$/ =~ value
					if /^taken_food_(.*)$/ =~ value
						ref["taken"]["food"].push($1)
					elsif /^taken_seasoning_(.*)$/ =~ value
						ref["taken"]["seasoning"].push($1)
					elsif /^taken_utensil_(.*)$/ =~ value
						ref["taken"]["utensil"].push($1)
					end
				elsif /^put_.*$/ =~ value
					if /^put_food_(.*)$/ =~ value
						ref["put"]["food"].push($1)
					elsif /^put_seasoning_(.*)$/ =~ value
						ref["put"]["seasoning"].push($1)
					elsif /^put_utensil_(.*)$/ =~ value
						ref["put"]["utensil"].push($1)
					end
				else
					ref["other"].push(value)
				end
			}
			# delay
			delay = -1
			if trigger["delay"] == nil
				delay = 0
			else
				delay = trigger["delay"]
			end
			hash_recipe["video"][video_id]["trigger"].push({"timing"=>timing, "ref"=>ref, "delay"=>delay})
		}
	end
	return hash_recipe
end
