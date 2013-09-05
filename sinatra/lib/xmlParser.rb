#!/usr/bin/ruby

require 'rubygems'
require 'json'
require 'nokogiri'

# step
# hash["step"][id] : step��id�򥭡��Ȥ��롥
# hash["step"][id]["parent"] = [id1, id2, ...] : step��parent�ꥹ��
# hash["step"][id]["chain"] = id : step��chain
# hash["step"][id]["priority"] = number : step��priority��
# hash["step"][id]["trigger"] = [[timing, ref, delay], [...], ...] : step��trigger�ꥹ��
# hash["step"][id]["substep"] = [id, id, ...] : step��substep�ꥹ��
# hash["sorted_step"] = [[priproty, id], [...], ...] : step��priority��˥����Ȥ���step��id�ꥹ��
def get_step(doc, hash)
	priority_list = []
	doc.xpath("//recipe/directions/step").each{|node|
		##### attribute�μ��Ф� #####
		# id�ϻ��ĤϤ�
		step_id = node["id"]
		# parent����Ĥʤ��
		unless node["parent"] == nil
			hash["step"][step_id]["parent"] = []
			node["parent"].split(" ").each{|v|
				hash["step"][step_id]["parent"].push(v)
			}
		end
		# chain����Ĥʤ��
		unless node["chain"] == nil
			hash["step"][step_id]["chain"] = node["chain"]
		end
		# priority�ϳ������
		# ����Ū��element�ε��ҽ���ɤ����priority_list���������Ƥ���
		# priority�����ꤵ��Ƥ���Ȥ��Τߡ�����˹�碌�����֤��������롥
		# ���ֽ���priority����ꤵ�줿step�ΰ��֤����Ȥʤäƿ�����뤳�Ȥˤʤ�Τǡ���Ŭ�ʽ�����¤٤��Ƥ���櫓�ǤϤʤ���
		# chain�ΤĤʤ����ޤ��priority�ν��֤����٤��������񤷤��ΤǤ��ʤ���
		unless node["priority"] == nil
			# priority����Ĥʤ�С�priority_list����Ǽ�ʬ��꾮������Τ�������������
			# priority_list������nil�ʤ�С����ָ�����������
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
			# priority������ʤ��ʤ�С�nil�Ȥ���priority_list�ΰ��ָ�����������
			priority_list.push([step_id,nil])
		end
		##### element�μ��Ф� #####
		# trigger����Ĥʤ��
		unless doc.xpath("//recipe/directions/step[@id=\"#{step_id}\"]/trigger")[0] == nil
			hash["step"][step_id]["trigger"] = []
			doc.xpath("//recipe/directions/step[@id=\"#{step_id}\"]/trigger").each{|node2|
				# trigger��timing����Ĥʤ��
				timing = nil
				unless node2["timing"] == nil
					timing = node2["timing"]
				end
				if timing == nil
					timing = "start"
				end
				# trigger��ref����ĤϤ���ref��ʣ���Ĥβ�ǽ�������
				ref = []
				node2["ref"].split(" ").each{|v|
					ref.push(v)
				}
				# trigger��delay����Ĥʤ��
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
		# substep�ϰ�İʾ���ĤϤ�
		hash["step"][step_id]["substep"] = []
		doc.xpath("//recipe/directions/step[@id=\"#{step_id}\"]/substep").each{|node2|
			# substep��id����ĤϤ�
			substep_id = node2["id"]
			hash["step"][step_id]["substep"].push(substep_id)
			hash = get_substep(doc, hash, step_id, substep_id)
		}
	}
	# priority_list�˹�碌��priority������
	for i in 0..(priority_list.size-1)
		hash["step"][priority_list[i][0]]["priority"] = 100 - i
	end
	# step��priority�ν���¤٤�hash[sorted_step]�����
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
# hash["substep"][id] : substep��id
# hash["substep"][id]["parent_step"] = id : parent node��step��id
# hash["substep"][id]["order"] = order_num : substep��order���ֹ�
# hash["substep"][id]["trigger"] = [[timing, ref, delay], [...], ...] : substep��trigger�ꥹ��
# hash["substep"][id]["notification"] = [id, id, ...] : notification��id�ꥹ��
# hash["substep"][id]["audio"] = [id] : audio��id���ص�������ˤ��Ƥ��롥
# hash["substep"][id]["video"] = [id] : video��id���ص�������ˤ��Ƥ��롥
# hash["substep"][id]["next_substep"] = id : ����substep��id
def get_substep(doc, hash, step_id, substep_id)
	unless step_id == nil
		# directions�ʲ���step�ʲ��˽񤫤�Ƥ���subste��parent_step�����
		hash["substep"][substep_id]["parent_step"] = step_id
	end
	##### attribute�μ��Ф� #####
	# order����Ĥʤ��
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]")[0]["order"] == nil
		hash["substep"][substep_id]["order"] = doc.xpath("//substep[@id=\"#{substep_id}\"]")[0]["order"]
	end
	##### element�μ��Ф� #####
	# trigger����Ĥʤ��
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/trigger")[0] == nil
		hash["substep"][substep_id]["trigger"] = []
		doc.xpath("//substep[@id=\"#{substep_id}\"]/trigger").each{|node2|
			# trigger��timing����Ĥʤ��
			timing = nil
			unless node2["timing"] == nil
				timing = node2["timing"]
			end
			if timing == nil
				timing = "start"
			end
			# trigger��ref����ĤϤ���ref��ʣ���Ĥβ�ǽ�������
			ref = []
			node2["ref"].split(" ").each{|v|
				ref.push(v)
			}
			# trigger��delay����Ĥʤ��
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
	# notification����Ĥʤ��
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/notification")[0] == nil
		hash["substep"][substep_id]["notification"] = []
		doc.xpath("//substep[@id=\"#{substep_id}\"]/notification").each{|node|
			notification_id = node["id"]
			hash["substep"][substep_id]["notification"].push(notification_id)
			hash = get_notification(doc, hash, substep_id, notification_id)
		}
	end
	# audio����Ĥʤ��
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/audio")[0] == nil
		audio_id = doc.xpath("//substep[@id=\"#{substep_id}\"]/audio")[0]["id"]
		hash["substep"][substep_id]["audio"] = [audio_id]
		hash = get_audio(doc, hash, substep_id, nil, audio_id)
	end
	# video����Ĥʤ��
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/video")[0] == nil
		video_id = doc.xpath("//substep[@id=\"#{substep_id}\"]/video")[0]["id"]
		hash["substep"][substep_id]["video"] = [video_id]
		hash = get_video(doc, hash, substep_id, video_id)
	end
	# ����substep����Ĥʤ��
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].next_sibling == nil
		if doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].next_sibling.name == "substep"
			next_substep = doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].next_sibling["id"]
			hash["substep"][substep_id]["next_substep"] = next_substep
		end
	end
	return hash
end

# notification
# hash["notification"][id] : notification��id
# hash["notification"][id]["parent_substep"] = id : parent node��substep��id
# hash["notification"][id]["trigger"] = [[timing, ref, delay], [...], ...] : notification��trigger�ꥹ��
# hash["notification"][id]["audio"] = id : notification��audio��
def get_notification(doc, hash, substep_id, notification_id)
	unless substep_id == nil
		hash["notification"][notification_id]["parent_substep"] = substep_id
	end
	##### element�μ��Ф� #####
	# trigger����Ĥʤ��
	unless doc.xpath("//notification[@id=\"#{notification_id}\"]/trigger")[0] == nil
		hash["notification"][notification_id]["trigger"] = []
		doc.xpath("//notification[@id=\"#{notification_id}\"]/trigger").each{|node2|
			# trigger��timing����Ĥʤ��
			timing = nil
			unless node2["timing"] == nil
				timing = node2["timing"]
			end
			if timing == nil
				timing = "start"
			end
			# trigger��ref����ĤϤ���ref��ʣ���Ĥβ�ǽ�������
			ref = []
			node2["ref"].split(" ").each{|v|
				ref.push(v)
			}
			# trigger��delay����Ĥʤ��
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
	# audio����Ĥʤ��
	unless doc.xpath("//notification[@id=\"#{notification_id}\"]/audio")[0] == nil
		audio_id = doc.xpath("//notification[@id=\"#{notification_id}\"]/audio")[0]["id"]
		hash["notification"][notification_id]["audio"] = audio_id
		hash = get_audio(doc, hash, nil, notification_id, audio_id)
	end
	return hash
end

# audio
# hash["audio"][id] : audio��id
# hash["audio"][id]["parent_substep"] = id : parent node��substep��id
# hash["audio"][id]["parent_notification"] = id : parent node��notification��id
# hash["audio"][id]["trigger"] = [[timing, ref, delay], [...], ...] : notification��trigger�ꥹ��
def get_audio(doc, hash, substep_id, notification_id, audio_id)
	unless substep_id == nil
		hash["audio"][audio_id]["parent_substep"] = substep_id
	end
	unless notification_id == nil
		hash["audio"][audio_id]["parent_notification"] = notification_id
	end
	##### element�μ��Ф� #####
	# trigger����Ĥʤ��
	unless doc.xpath("//audio[@id=\"#{audio_id}\"]/trigger")[0] == nil
		hash["audio"][audio_id]["trigger"] = []
		doc.xpath("//audio[@id=\"#{audio_id}\"]/trigger").each{|node2|
			# trigger��timing����Ĥʤ��
			timing = nil
			unless node2["timing"] == nil
				timing = node2["timing"]
			end
			if timing == nil
				timing = "start"
			end
			# trigger��ref����ĤϤ���ref��ʣ���Ĥβ�ǽ�������
			ref = []
			node2["ref"].split(" ").each{|v|
				ref.push(v)
			}
			# trigger��delay����Ĥʤ��
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
# hash["video"][id] : video��id
# hash["video"][id]["parent_substep"] = id : parent node��substep��id
# hash["video"][id]["trigger"] = [[timing, ref, delay], [...], ...] : notification��trigger�ꥹ��
def get_video(doc, hash, substep_id, video_id)
	hash["video"][video_id]["parent_substep"] = substep_id
	##### element�μ��Ф� #####
	# trigger����Ĥʤ��
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/video[@id=\"#{video_id}\"]/trigger")[0] == nil
		hash["video"][video_id]["trigger"] = []
		doc.xpath("//substep[@id=\"#{substep_id}\"]/video[@id=\"#{video_id}\"]/trigger").each{|node2|
			# trigger��timing����Ĥʤ��
			timing = nil
			unless node2["timing"] == nil
				timing = node2["timing"]
			end
			if timing == nil
				timing = "start"
			end
			# trigger��ref����ĤϤ���ref��ʣ���Ĥβ�ǽ�������
			ref = []
			node2["ref"].split(" ").each{|v|
				ref.push(v)
			}
			# trigger��delay����Ĥʤ��
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
