#!/usr/bin/ruby

require 'rubygems'
require 'json'
require 'rexml/document'

$LOAD_PATH.push(File.dirname(__FILE__))
require 'lib/utils.rb'

# CURRENT��substep��html_contents��ɽ��������DetailDraw̿�ᡥ
def detailDraw(hash_mode)
	begin
		orders = []
		hash_mode["substep"]["mode"].each{|key, value|
			# CURREN��substep�ϰ�Ĥ����ʤΤϤ��ˡ�
			if value[2] == "CURRENT"
				orders.push({"DetailDraw"=>{"id"=>key}})
				break
			end
		}
	rescue => e
		p e
		return [], false
	end

	return orders, true
end

# CURRENT��audio��video�����������Play̿�ᡥ
def play(time)
	orders = []
	media = ["audio", "video"]
	media.each{|v|
		@hash_mode[v]["mode"].each{|key, value|
			if value[0] == "CURRENT"
				# trigger�ο���1�İʾ�ΤȤ���
				if @doc.emelents["//#{v}[@id=\"#{key}\"]/trigger[1]"] != nil
					# trigger��ʣ���Ĥξ�硤�ɤ�����Τ��ͤ��Ƥ��ʤ���
					@doc.get_elements("//#{v}[@id=\"#{key}\"]/trigger[1]").each{|node|
						orders.push({"Play"=>{"id"=>key, "delay"=>node.attributes.get_attribute("delay").value}})
						finish_time = time + node.attributes.get_attribute("delay").value.to_i * 1000
						@hash_mode[v]["mode"][key][1] = finish_time
					}
				else # trigger��0�ĤΤȤ���
					# trigger��̵�����Ϻ���̿��ϽФ��ʤ�����hash_mode�Ϥɤ��ѹ�����Τ��ͤ��Ƥ��ʤ���
					# @hash_mode[v]["mode"][key][1] = ?
					return []
				end
			end
		}
	}
	open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
		io.puts(JSON.pretty_generate(@hash_mode))
	}
	return orders
end


# �����Ԥ����֤�audio��video��notification����ߤ���Cancel̿�ᡥ
def cancel(session_id, doc, hash_mode, *id)
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
						if doc.elements["//notification[@id=\"#{key}\"]/audio"] != nil
							audio_id = doc.elements["//notification[@id=\"#{key}\"]/audio"].attributes.get_attribute("id").value
							hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				}
			end
		else # ��ߤ������ǥ����ˤĤ��ƻ��꤬�����硥
			id.each{|v|
				# ���ꤵ�줿��ǥ�����element name��Ĵ����
				element_name = searchElementName(session_id, v)
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
						if doc.elements["//notification[@id=\"#{v}\"]/audio"] != nil
							audio_id = doc.elements["//notification[@id=\"#{v}\"]/audio"].attributes.get_attribute("id").value
							hash_mode["audio"]["mode"][audio_id] = ["FINISHED", -1]
						end
					end
				else # ���ꤵ�줿��Τ�audio��video��notification��̵����硥
					return [], "invalid_params"
				end
			}
		end
		open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
			io.puts(JSON.pretty_generate(hash_mode))
		}
	rescue => e
		p e
		return [], "internal_error"
	end

	return orders, "success"
end
