#!?usr/bin/ruby

require 'rubygems'
require 'json'
$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/utils.rb'

# CURRENT��substep��html_contents��ɽ��������DetailDraw̿�ᡥ
def detailDraw(hash_mode)
	orders = []
	hash_mode["substep"]["mode"].each{|key, value|
		# CURREN��substep�ϰ�Ĥ����ʤΤϤ��ˡ�
		if value[2] == "CURRENT"
			orders.push({"DetailDraw"=>{"id"=>key}})
			break
		end
	}
	return orders
end

# CURRENT��audio��video�����������Play̿�ᡥ
def play(hash_recipe, hash_mode, time)
	orders = []
	media = ["audio", "video"]
	media.each{|v|
		hash_mode[v]["mode"].each{|key, value|
			if value[0] == "CURRENT"
				# trigger�ο���1�İʾ�ΤȤ���
				if hash_recipe[v][key].key?("trigger")
					# trigger��ʣ���Ĥξ�硤�ɤ�����Τ��ͤ��Ƥ��ʤ���
					orders.push({"Play"=>{"id"=>key, "delay"=>hash_recipe[v][key]["trigger"][0][2].to_i}})
					finish_time = time + hash_recipe[v][key]["trigger"][0][2].to_i * 1000
					hash_mode[v]["mode"][key][1] = finish_time
				else # trigger��0�ĤΤȤ���
					# trigger��̵�����Ϻ���̿��ϽФ��ʤ�����hash_mode�Ϥɤ��ѹ�����Τ��ͤ��Ƥ��ʤ���
					# @hash_mode[v]["mode"][key][1] = ?
					return []
				end
			end
		}
	}
	return orders, hash_mode
end

# CURRENT��notification�����������Notify̿�ᡥ
def notify(hash_recipe, hash_mode, time)
	orders = []
	hash_mode["notification"]["mode"].each{|key, value|
		if value[0] == "CURRENT"
			# notification��trigger��ɬ�����롥
			# trigger��ʣ���Ĥξ�硤�ɤ�����Τ��ͤ��Ƥ��ʤ���
			orders.push({"Notify"=>{"id"=>key, "delay"=>hash_recipe["notification"][key]["trigger"][0][2].to_i}})
			finish_time = time + hash_recipe["notification"][key]["trigger"][0][2].to_i * 1000
			# notification���ü�ʤΤǡ����̤�KEEP���ѹ����롥
			hash_mode["notification"]["mode"][key] = ["KEEP", finish_time]
		end
	}
	return orders, hash_mode
end

# �����Ԥ����֤�audio��video��notification����ߤ���Cancel̿�ᡥ
def cancel(hash_recipe, hash_mode, *id)
	begin
		orders = []
		# �ä���ߤ������ǥ����ˤĤ��ƻ��̵꤬�����
		if id == []
			# audio��video�ν�����
			# Cancel������٤���Τϡ�STOP�ˤʤäƤ���Ϥ���
			media = ["audio", "video"]
			media.each{|v|
				if hash_mode.key?(v)
					hash_mode[v]["mode"].each{|key, value|
						if value[0] == "STOP"
							orders.push({"Cancel"=>{"id"=>key}})
							# STOP����FINISHED���ѹ���
							hash_mode[v]["mode"][key] = ["FINISHED", -1]
						end
					}
				end
			}
			# notification�ν�����
			# Cancel������٤���Τϡ�STOP�ΤʤäƤ���Ϥ���
			if hash_mode.key?("notification")
				hash_mode["notification"]["mode"].each{|key, value|
					if value[0] == "STOP"
						orders.push({"Cancel"=>{"id"=>key}})
						# STOP����FINISHED���ѹ���
						hash_mode["notification"]["mode"][key] = ["FINISHED", -1]
						# audio����notification�ξ�硤audio��FINISHED���ѹ���
						if hash_recipe["notification"][key].key?("audio")
							audio_id = hash_recipe["notification"][key]["audio"]
							hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				}
			end
		else # ��ߤ������ǥ����ˤĤ��ƻ��꤬�����硥
			id.each{|v|
				# ���ꤵ�줿��ǥ�����element name��Ĵ����
				element_name = search_ElementName(hash_recipe, v)
				# audio��video�ξ�硥
				if element_name == "audio" || element_name == "video"
					# ���ꤵ�줿��Τ������Ԥ����ɤ����Ȥꤢ����Ĵ�٤롤
					if hash_mode[element_name]["mode"][v][0] == "CURRENT"
						# Cancel����FINISHED�ˡ�
						orders.push({"Cancel"=>{"id"=>v}})
						hash_mode[element_name]["mode"][v] = ["FINISHED", -1]
					end
				elsif element_name == "notification" # notification�ξ�硥
					# ���ꤵ�줿notification�������Ԥ����ɤ����Ȥꤢ����Ĵ�٤롥
					if hash_mode["notification"]["mode"][v][0] == "KEEP"
						# Cancel����FINISHED�ˡ�
						orders.push({"Cancel"=>{"id"=>v}})
						hash_mode["notification"]["mode"][v][0] = ["FINISHED", -1]
						# audio�����notification��audio��FINISHED�ˡ�
						if hash_recipe["notification"][v].key?("audio")
							audio_id = hash_recipe["notification"][v]["audio"]
							hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				else # ���ꤵ�줿��Τ�audio��video��notification��̵����硥
					return [], hash_mode, "invalid params"
				end
			}
		end
	rescue => e
		p e
		return [], hash_mode, "internal error"
	end

	return orders, hash_mode, "success"
end

# �ʥӲ��̤�ɽ������ꤹ��NaviDraw̿�ᡥ
def naviDraw(hash_recipe, hash_mode)
	# sorted_step�ν��ɽ�������롥
	orders = Array.new()
	orders.push({"NaviDraw"=>{"steps"=>[]}})
	hash_recipe["sorted_step"].each{|v|
		id = v[1]
		visual = nil
		if hash_mode["step"]["mode"][id][2] == "CURRENT"
			visual = "CURRENT"
		else
			visual = hash_mode["step"]["mode"][id][0]
		end
		if hash_mode["step"]["mode"][id][1] == "is_finished"
			orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
		elsif hash_mode["step"]["mode"][id][1] == "NOT_YET"
			orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
		end
		# CURRENT��step�ξ�硤substep��ɽ�������롥
		if visual == "CURRENT"
			hash_recipe["step"][id]["substep"].each{|id|
				visual = nil
				if hash_mode["substep"]["mode"][id][2] == "CURRENT"
					visual = "CURRENT"
				else
					visual = hash_mode["substep"]["mode"][id][0]
				end
				if hash_mode["substep"]["mode"][id][1] == "is_finished"
					orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
				else
					orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
				end
			}
		end
		# NAVI_MENU�����򤵤줿��Τ⡤substep��ɽ�������롥��̤�б���
		if hash_mode["step"]["mode"][id][2] == "clicked_with_NAVI_MENU"
			hash_recipe["step"][id]["substep"].each{|id|
				visual = nil
				if hash_mode["substep"]["mode"][id][2] == "CURRENT"
					visual = "CURRENT"
				else
					visual = hash_mode["substep"]["mode"][id][0]
				end
				if hash_mode["substep"]["mode"][id][1] == "is_finished"
					orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>1})
				else
					orders[0]["NaviDraw"]["steps"].push({"id"=>id, "visual"=>visual, "is_finished"=>0})
				end
			}
		end
	}
	return orders
end
