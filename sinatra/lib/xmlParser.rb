#!/usr/bin/ruby

require 'rubygems'
require 'json'
require 'nokogiri'

# step
# hash["step"][id] : stepのidをキーとする．
# hash["step"][id]["parent"] = [id1, id2, ...] : stepのparentリスト
# hash["step"][id]["chain"] = id : stepのchain
# hash["step"][id]["priority"] = number : stepのpriority．
# hash["step"][id]["trigger"] = [[timing, ref, delay], [...], ...] : stepのtriggerリスト
# hash["step"][id]["substep"] = [id, id, ...] : stepのsubstepリスト
# hash["sorted_step"] = [[priproty, id], [...], ...] : stepのpriority順にソートしたstepのidリスト
def get_step(doc, hash)
	priority_list = []
	doc.xpath("//recipe/directions/step").each{|node|
		##### attributeの取り出し #####
		# idは持つはず
		step_id = node["id"]
		# parentを持つならば
		unless node["parent"] == nil
			hash["step"][step_id]["parent"] = []
			node["parent"].split(" ").each{|v|
				hash["step"][step_id]["parent"].push(v)
			}
		end
		# chainを持つならば
		unless node["chain"] == nil
			hash["step"][step_id]["chain"] = node["chain"]
		end
		# priorityは割と面倒
		# 基本的にelementの記述順序どおりにpriority_listに代入していく
		# priorityが指定されているときのみ，それに合わせた位置に代入する．
		# 一番初めにpriorityを指定されたstepの位置が基準となって色々やることになるので，最適な順序で並べられているわけではない．
		# chainのつながりも含めてpriorityの順番を決めるべきだが，難しいのでやらない．
		unless node["priority"] == nil
			# priorityを持つならば，priority_listの中で自分より小さいものの前に代入する
			# priority_listが全てnilならば，一番後ろに代入する
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
					end
				end
			end
		else
			# priorityを持たないならば，nilとしてpriority_listの一番後ろに代入する
			priority_list.push([step_id,nil])
		end
		##### elementの取り出し #####
		# triggerを持つならば
		unless doc.xpath("//recipe/directions/step[@id=\"#{step_id}\"]/trigger")[0] == nil
			hash["step"][step_id]["trigger"] = []
			doc.xpath("//recipe/directions/step[@id=\"#{step_id}\"]/trigger").each{|node2|
				# triggerがtimingを持つならば
				timing = nil
				unless node2["timing"] == nil
					timing = node2["timing"]
				end
				if timing == nil
					timing = "start"
				end
				# triggerはrefを持つはず（refは複数個の可能性あり）
				ref = []
				node2["ref"].split(" ").each{|v|
					ref.push(v)
				}
				# triggerがdelayを持つならば
				delay = -1
				unless node2["delay"] == nil
					delay = node2["delay"]
				end
				if delay == -1
					delay = 0
				end
				hash["step"][step_id]["trigger"].push([timing, ref, delay])
			}
		end
		# substepは一つ以上持つはず
		hash["step"][step_id]["substep"] = []
		doc.xpath("//recipe/directions/step[@id=\"#{step_id}\"]/substep").each{|node2|
			# substepはidを持つはず
			substep_id = node2["id"]
			hash["step"][step_id]["substep"].push(substep_id)
			hash = get_substep(doc, hash, step_id, substep_id)
		}
	}
	# priority_listに合わせてpriorityの設定
	for i in 0..(priority_list.size-1)
		hash["step"][priority_list[i][0]]["priority"] = 100 - i
	end
	# stepをpriorityの順に並べたhash[sorted_step]を作成
	hash["sorted_step"] = []
	hash["step"].each{|key, value|
		hash["sorted_step"].push([value["priority"], key])
	}
	hash["sorted_step"].sort!{|v1, v2|
		v2[0] <=> v1[0]
	}

	return hash
end

# substep
# hash["substep"][id] : substepのid
# hash["substep"][id]["parent_step"] = id : parent nodeなstepのid
# hash["substep"][id]["order"] = order_num : substepのorderの番号
# hash["substep"][id]["trigger"] = [[timing, ref, delay], [...], ...] : substepのtriggerリスト
# hash["substep"][id]["notification"] = [id, id, ...] : notificationのidリスト
# hash["substep"][id]["audio"] = [id] : audioのid．便宜上配列にしている．
# hash["substep"][id]["video"] = [id] : videoのid．便宜上配列にしている．
# hash["substep"][id]["next_substep"] = id : 次のsubstepのid
def get_substep(doc, hash, step_id, substep_id)
	unless step_id == nil
		# directions以下のstep以下に書かれているsubsteはparent_stepを持つ
		hash["substep"][substep_id]["parent_step"] = step_id
	end
	##### attributeの取り出し #####
	# orderを持つならば
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]")[0]["order"] == nil
		hash["substep"][substep_id]["order"] = doc.xpath("//substep[@id=\"#{substep_id}\"]")[0]["order"]
	end
	##### elementの取り出し #####
	# triggerを持つならば
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/trigger")[0] == nil
		hash["substep"][substep_id]["trigger"] = []
		doc.xpath("//substep[@id=\"#{substep_id}\"]/trigger").each{|node2|
			# triggerがtimingを持つならば
			timing = nil
			unless node2["timing"] == nil
				timing = node2["timing"]
			end
			if timing == nil
				timing = "start"
			end
			# triggerはrefを持つはず（refは複数個の可能性あり）
			ref = []
			node2["ref"].split(" ").each{|v|
				ref.push(v)
			}
			# triggerがdelayを持つならば
			delay = -1
			unless node2["delay"] == nil
				delay = node2["delay"]
			end
			if delay == -1
				delay = 0
			end
			hash["substep"][substep_id]["trigger"].push([timing, ref, delay])
		}
	end
	# notificationを持つならば
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/notification")[0] == nil
		hash["substep"][substep_id]["notification"] = []
		doc.xpath("//substep[@id=\"#{substep_id}\"]/notification").each{|node|
			notification_id = node["id"]
			hash["substep"][substep_id]["notification"].push(notification_id)
			hash = get_notification(doc, hash, substep_id, notification_id)
		}
	end
	# audioを持つならば
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/audio")[0] == nil
		audio_id = doc.xpath("//substep[@id=\"#{substep_id}\"]/audio")[0]["id"]
		hash["substep"][substep_id]["audio"] = [audio_id]
		hash = get_audio(doc, hash, substep_id, nil, audio_id)
	end
	# videoを持つならば
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/video")[0] == nil
		video_id = doc.xpath("//substep[@id=\"#{substep_id}\"]/video")[0]["id"]
		hash["substep"][substep_id]["video"] = [video_id]
		hash = get_video(doc, hash, substep_id, video_id)
	end
	# 次のsubstepを持つならば
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].next_sibling == nil
		if doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].next_sibling.name == "substep"
			next_substep = doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].next_sibling["id"]
			hash["substep"][substep_id]["next_substep"] = next_substep
		end
	end
	return hash
end

# notification
# hash["notification"][id] : notificationのid
# hash["notification"][id]["parent_substep"] = id : parent nodeなsubstepのid
# hash["notification"][id]["trigger"] = [[timing, ref, delay], [...], ...] : notificationのtriggerリスト
# hash["notification"][id]["audio"] = id : notificationのaudio．
def get_notification(doc, hash, substep_id, notification_id)
	unless substep_id == nil
		hash["notification"][notification_id]["parent_substep"] = substep_id
	end
	##### elementの取り出し #####
	# triggerを持つならば
	unless doc.xpath("//notification[@id=\"#{notification_id}\"]/trigger")[0] == nil
		hash["notification"][notification_id]["trigger"] = []
		doc.xpath("//notification[@id=\"#{notification_id}\"]/trigger").each{|node2|
			# triggerがtimingを持つならば
			timing = nil
			unless node2["timing"] == nil
				timing = node2["timing"]
			end
			if timing == nil
				timing = "start"
			end
			# triggerはrefを持つはず（refは複数個の可能性あり）
			ref = []
			node2["ref"].split(" ").each{|v|
				ref.push(v)
			}
			# triggerがdelayを持つならば
			delay = -1
			unless node2["delay"] == nil
				delay = node2["delay"]
			end
			if delay == -1
				delay = 0
			end
			hash["notification"][notification_id]["trigger"].push([timing, ref, delay])
		}
	end
	# audioを持つならば
	unless doc.xpath("//notification[@id=\"#{notification_id}\"]/audio")[0] == nil
		audio_id = doc.xpath("//notification[@id=\"#{notification_id}\"]/audio")[0]["id"]
		hash["notification"][notification_id]["audio"] = audio_id
		hash = get_audio(doc, hash, nil, notification_id, audio_id)
	end
	return hash
end

# audio
# hash["audio"][id] : audioのid
# hash["audio"][id]["parent_substep"] = id : parent nodeなsubstepのid
# hash["audio"][id]["parent_notification"] = id : parent nodeなnotificationのid
# hash["audio"][id]["trigger"] = [[timing, ref, delay], [...], ...] : notificationのtriggerリスト
def get_audio(doc, hash, substep_id, notification_id, audio_id)
	unless substep_id == nil
		hash["audio"][audio_id]["parent_substep"] = substep_id
	end
	unless notification_id == nil
		hash["audio"][audio_id]["parent_notification"] = notification_id
	end
	##### elementの取り出し #####
	# triggerを持つならば
	unless doc.xpath("//audio[@id=\"#{audio_id}\"]/trigger")[0] == nil
		hash["audio"][audio_id]["trigger"] = []
		doc.xpath("//audio[@id=\"#{audio_id}\"]/trigger").each{|node2|
			# triggerがtimingを持つならば
			timing = nil
			unless node2["timing"] == nil
				timing = node2["timing"]
			end
			if timing == nil
				timing = "start"
			end
			# triggerはrefを持つはず（refは複数個の可能性あり）
			ref = []
			node2["ref"].split(" ").each{|v|
				ref.push(v)
			}
			# triggerがdelayを持つならば
			delay = -1
			unless node2["delay"] == nil
				delay = node2["delay"]
			end
			if delay == -1
				delay = 0
			end
			hash["audio"][audio_id]["trigger"].push([timing, ref, delay])
		}
	end
	return hash
end

# video
# hash["video"][id] : videoのid
# hash["video"][id]["parent_substep"] = id : parent nodeなsubstepのid
# hash["video"][id]["trigger"] = [[timing, ref, delay], [...], ...] : notificationのtriggerリスト
def get_video(doc, hash, substep_id, video_id)
	hash["video"][video_id]["parent_substep"] = substep_id
	##### elementの取り出し #####
	# triggerを持つならば
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/video[@id=\"#{video_id}\"]/trigger")[0] == nil
		hash["video"][video_id]["trigger"] = []
		doc.xpath("//substep[@id=\"#{substep_id}\"]/video[@id=\"#{video_id}\"]/trigger").each{|node2|
			# triggerがtimingを持つならば
			timing = nil
			unless node2["timing"] == nil
				timing = node2["timing"]
			end
			if timing == nil
				timing = "start"
			end
			# triggerはrefを持つはず（refは複数個の可能性あり）
			ref = []
			node2["ref"].split(" ").each{|v|
				ref.push(v)
			}
			# triggerがdelayを持つならば
			delay = -1
			unless node2["delay"] == nil
				delay = node2["delay"]
			end
			if delay == -1
				delay = 0
			end
			hash["video"][video_id]["trigger"].push([timing, ref, delay])
		}
	end
	return hash
end
