#!/usr/bin/ruby

require 'rubygems'
require 'json'
require 'rexml/document'

def start_action(session_id, contents)
	`mkdir -p records/#{session_id}`

	`touch records/#{session_id}/#{session_id}.log`
	`touch records/#{session_id}/#{session_id}_error.log`
	`touch records/#{session_id}/#{session_id}_recipe.xml`

	fo = open("records/#{session_id}/hoge.xml", "w")
	fo.puts(contents)
	fo.close()
	`cat records/#{session_id}/hoge.xml | tr -d "\r" | tr -d "\n"  | tr -d "\t" > records/#{session_id}/#{session_id}_recipe.xml`

	doc = REXML::Document.new(open("records/#{session_id}/#{session_id}_recipe.xml"))

	# idテーブルファイルの作成
	hash_id = Hash.new{|h, k| h[k] = {}}
	doc.get_elements("//*").each{|node|
		if node.attributes.get_attribute("id") != nil
			if hash_id.key?("#{node.name}")
				hash_id["#{node.name}"]["id"].push(node.attributes.get_attribute("id").value)
			else
				hash_id["#{node.name}"]["id"] = []
				hash_id["#{node.name}"]["id"].push(node.attributes.get_attribute("id").value)
			end
		end
	}
	open("records/#{session_id}/#{session_id}_table.txt", "w"){|io|
		io.puts(JSON.pretty_generate(hash_id))
	}

	hash_mode = Hash.new{|h, k| h[k] = Hash.new(&h.default_proc)}
	sorted_step = []

	# modeファイル及びsortedファイ作成
	if hash_id.key?("step")
		hash_id["step"]["id"].each{|value|
			priority = doc.elements["//step[@id=\"#{value}\"]"].attributes.get_attribute("priority").value.to_i # ここが遅い．REXMLだから．
			hash_mode["step"]["mode"][value] = ["OTHERS","NOT_YET","NOT_CURRENT"]
			sorted_step.push([priority, value])
		}
		sorted_step.sort!{|v1, v2|
			v2[0] <=> v1[0]
		}
	end
	if hash_id.key?("substep")
		hash_id["substep"]["id"].each{|value|
			hash_mode["substep"]["mode"][value] = ["OTHERS","NOT_YET","NOT_CURRENT"]
		}
	end
	if hash_id.key?("audio")
		hash_id["audio"]["id"].each{|value|
			hash_mode["audio"]["mode"][value] = ["NOT_YET", -1]
		}
	end
	if hash_id.key?("video")
		hash_id["video"]["id"].each{|value|
			hash_mode["video"]["mode"][value] = ["NOT_YET", -1]
		}
	end
	if hash_id.key?("notification")
		hash_id["notification"]["id"].each{|value|
			hash_mode["notification"]["mode"][value] = ["NOT_YET", -1]
		}
	end

	open("records/#{session_id}/#{session_id}_mode.txt", "w"){|io|
		io.puts(JSON.pretty_generate(hash_mode))
	}
	open("records/#{session_id}/#{session_id}_sortedstep.txt", "w"){|io|
		io.puts(JSON.pretty_generate(sorted_step))
	}
end

