#!/usr/bin/ruby

# END�ꥯ�����Ȥξ���mode���åץǡ���
def finish_action(session_id)
	begin
		hash_mode = Hash.new()
		open("records/#{session_id}/#{session_id}_mode.txt", "r"){|io|
			hash_mode = JSON.load(io)
		}
		# ����������Ԥ���ǥ�����STOP�ˤ��롥
		media = ["audio", "video", "notification"]
		media.each{|v|
			hash_mode[v]["mode"].each{|key, value|
				if value[0] == "CURRENT"
					hash_mode[v]["mode"][key][0] = "STOP"
				end
			}
		}
	rescue => e
		p e
		return [], "internal_error"
	end

	return hash_mode, "success"
end

