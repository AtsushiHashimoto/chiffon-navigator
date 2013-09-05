#!/usr/bin/ruby

require 'rubygems'
require 'json'
require 'nokogiri'

def parse_xml(xmlfile)
	doc = Nokogiri::XML(open(xmlfile))
	hash_recipe = Hash.new{|h,k| h[k]=Hash.new(&h.default_proc)}
	hash_mode = Hash.new{|h,k| h[k]=Hash.new(&h.default_proc)}

	hash_recipe = get_step(doc, hash_recipe)
	# directions/substep�ν񤭽Ф�
	doc.xpath("//directions/substep").each{|node|
		substep_id = node["id"]
		hash_recipe = get_substep(doc, hash_recipe, nil, substep_id)
	}
	# recipe/notification�ν񤭽Ф�
	doc.xpath("//recipe/notification").each{|node|
		notification_id = node["id"]
		hash_recipe = get_notification(doc, hash_recipe, nil, notification_id)
	}
	# recipe/event�ν񤭽Ф�
	doc.xpath("//recipe/event").each{|node|
		event_id = node["id"]
		hash_recipe["event"][event_id] = 1
	}
	return hash_recipe
end

# step
# hash_recipe["step"][id] : step��id�򥭡��Ȥ��롥
# hash_recipe["step"][id]["parent"] = [id1, id2, ...] : step��parent�ꥹ��
# hash_recipe["step"][id]["chain"] = id : step��chain
# hash_recipe["step"][id]["priority"] = number : step��priority��
# hash_recipe["step"][id]["trigger"] = [[timing, ref, delay], [...], ...] : step��trigger�ꥹ��
# hash_recipe["step"][id]["substep"] = [id, id, ...] : step��substep�ꥹ��
# hash_recipe["sorted_step"] = [[priproty, id], [...], ...] : step��priority��˥����Ȥ���step��id�ꥹ��
def get_step(doc, hash_recipe)
	priority_list = []
	doc.xpath("//recipe/directions/step").each{|node|
		##### attribute�μ��Ф� #####
		# id�ϻ��ĤϤ�
		step_id = node["id"]
		# parent����Ĥʤ��
		unless node["parent"] == nil
			hash_recipe["step"][step_id]["parent"] = []
			node["parent"].split(" ").each{|v|
				hash_recipe["step"][step_id]["parent"].push(v)
			}
		end
		# chain����Ĥʤ��
		unless node["chain"] == nil
			hash_recipe["step"][step_id]["chain"] = node["chain"]
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
			hash_recipe["step"][step_id]["trigger"] = []
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
				hash_recipe["step"][step_id]["trigger"].push([timing, ref, delay])
			}
		end
		# substep�ϰ�İʾ���ĤϤ�
		hash_recipe["step"][step_id]["substep"] = []
		doc.xpath("//recipe/directions/step[@id=\"#{step_id}\"]/substep").each{|node2|
			# substep��id����ĤϤ�
			substep_id = node2["id"]
			hash_recipe["step"][step_id]["substep"].push(substep_id)
			hash_recipe = get_substep(doc, hash_recipe, step_id, substep_id)
		}
	}
	# priority_list�˹�碌��priority������
	for i in 0..(priority_list.size-1)
		hash_recipe["step"][priority_list[i][0]]["priority"] = 100 - i
	end
	# step��priority�ν���¤٤�hash_recipe[sorted_step]�����
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
# hash_recipe["substep"][id] : substep��id
# hash_recipe["substep"][id]["parent_step"] = id : parent node��step��id
# hash_recipe["substep"][id]["order"] = order_num : substep��order���ֹ�
# hash_recipe["substep"][id]["trigger"] = [[timing, ref, delay], [...], ...] : substep��trigger�ꥹ��
# hash_recipe["substep"][id]["notification"] = [id, id, ...] : notification��id�ꥹ��
# hash_recipe["substep"][id]["audio"] = [id] : audio��id���ص�������ˤ��Ƥ��롥
# hash_recipe["substep"][id]["video"] = [id] : video��id���ص�������ˤ��Ƥ��롥
# hash_recipe["substep"][id]["next_substep"] = id : ����substep��id
def get_substep(doc, hash_recipe, step_id, substep_id)
	unless step_id == nil
		# directions�ʲ���step�ʲ��˽񤫤�Ƥ���subste��parent_step�����
		hash_recipe["substep"][substep_id]["parent_step"] = step_id
	end
	##### attribute�μ��Ф� #####
	# order����Ĥʤ��
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]")[0]["order"] == nil
		hash_recipe["substep"][substep_id]["order"] = doc.xpath("//substep[@id=\"#{substep_id}\"]")[0]["order"]
	end
	##### element�μ��Ф� #####
	# trigger����Ĥʤ��
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/trigger")[0] == nil
		hash_recipe["substep"][substep_id]["trigger"] = []
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
			hash_recipe["substep"][substep_id]["trigger"].push([timing, ref, delay])
		}
	end
	# notification����Ĥʤ��
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/notification")[0] == nil
		hash_recipe["substep"][substep_id]["notification"] = []
		doc.xpath("//substep[@id=\"#{substep_id}\"]/notification").each{|node|
			notification_id = node["id"]
			hash_recipe["substep"][substep_id]["notification"].push(notification_id)
			hash_recipe = get_notification(doc, hash_recipe, substep_id, notification_id)
		}
	end
	# audio����Ĥʤ��
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/audio")[0] == nil
		audio_id = doc.xpath("//substep[@id=\"#{substep_id}\"]/audio")[0]["id"]
		hash_recipe["substep"][substep_id]["audio"] = [audio_id]
		hash_recipe = get_audio(doc, hash_recipe, substep_id, nil, audio_id)
	end
	# video����Ĥʤ��
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/video")[0] == nil
		video_id = doc.xpath("//substep[@id=\"#{substep_id}\"]/video")[0]["id"]
		hash_recipe["substep"][substep_id]["video"] = [video_id]
		hash_recipe = get_video(doc, hash_recipe, substep_id, video_id)
	end
	# ����substep����Ĥʤ��
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].next_sibling == nil
		next_node = doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].next_sibling
		if doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].next_sibling.name == "substep"
			next_substep = doc.xpath("//substep[@id=\"#{substep_id}\"]")[0].next_sibling["id"]
			hash_recipe["substep"][substep_id]["next_substep"] = next_substep
		end
	end
	return hash_recipe
end

# notification
# hash_recipe["notification"][id] : notification��id
# hash_recipe["notification"][id]["parent_substep"] = id : parent node��substep��id
# hash_recipe["notification"][id]["trigger"] = [[timing, ref, delay], [...], ...] : notification��trigger�ꥹ��
# hash_recipe["notification"][id]["audio"] = id : notification��audio��
def get_notification(doc, hash_recipe, substep_id, notification_id)
	unless substep_id == nil
		hash_recipe["notification"][notification_id]["parent_substep"] = substep_id
	end
	##### element�μ��Ф� #####
	# trigger����Ĥʤ��
	unless doc.xpath("//notification[@id=\"#{notification_id}\"]/trigger")[0] == nil
		hash_recipe["notification"][notification_id]["trigger"] = []
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
			hash_recipe["notification"][notification_id]["trigger"].push([timing, ref, delay])
		}
	end
	# audio����Ĥʤ��
	unless doc.xpath("//notification[@id=\"#{notification_id}\"]/audio")[0] == nil
		audio_id = doc.xpath("//notification[@id=\"#{notification_id}\"]/audio")[0]["id"]
		hash_recipe["notification"][notification_id]["audio"] = audio_id
		hash_recipe = get_audio(doc, hash_recipe, nil, notification_id, audio_id)
	end
	return hash_recipe
end

# audio
# hash_recipe["audio"][id] : audio��id
# hash_recipe["audio"][id]["parent_substep"] = id : parent node��substep��id
# hash_recipe["audio"][id]["parent_notification"] = id : parent node��notification��id
# hash_recipe["audio"][id]["trigger"] = [[timing, ref, delay], [...], ...] : notification��trigger�ꥹ��
def get_audio(doc, hash_recipe, substep_id, notification_id, audio_id)
	unless substep_id == nil
		hash_recipe["audio"][audio_id]["parent_substep"] = substep_id
	end
	unless notification_id == nil
		hash_recipe["audio"][audio_id]["parent_notification"] = notification_id
	end
	##### element�μ��Ф� #####
	# trigger����Ĥʤ��
	unless doc.xpath("//audio[@id=\"#{audio_id}\"]/trigger")[0] == nil
		hash_recipe["audio"][audio_id]["trigger"] = []
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
			hash_recipe["audio"][audio_id]["trigger"].push([timing, ref, delay])
		}
	end
	return hash_recipe
end

# video
# hash_recipe["video"][id] : video��id
# hash_recipe["video"][id]["parent_substep"] = id : parent node��substep��id
# hash_recipe["video"][id]["trigger"] = [[timing, ref, delay], [...], ...] : notification��trigger�ꥹ��
def get_video(doc, hash_recipe, substep_id, video_id)
	hash_recipe["video"][video_id]["parent_substep"] = substep_id
	##### element�μ��Ф� #####
	# trigger����Ĥʤ��
	unless doc.xpath("//substep[@id=\"#{substep_id}\"]/video[@id=\"#{video_id}\"]/trigger")[0] == nil
		hash_recipe["video"][video_id]["trigger"] = []
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
			hash_recipe["video"][video_id]["trigger"].push([timing, ref, delay])
		}
	end
	return hash_recipe
end
