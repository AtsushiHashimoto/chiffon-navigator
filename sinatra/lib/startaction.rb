#!/usr/bin/ruby

require 'rubygems'
require 'json'
require 'rexml/document'

require 'lib/utils.rb'

class StartAction
	def initialize(input)
		@session_id = input
		@doc = nil
		@hash_id = Hash.new{|h, k| h[k] = {}}
	end

	def makeLogfile(contents)
		`mkdir -p records/#{@session_id}`
		`touch records/#{@session_id}/#{@session_id}.log`
		`touch records/#{@session_id}/#{@session_id}_error.log`
		`touch records/#{@session_id}/#{@session_id}_recipe.xml`
		`touch records/#{@session_id}/#{@session_id}_table.txt`
		`touch records/#{@session_id}/#{@session_id}_mode.txt`
		`touch records/#{@session_id}/#{@session_id}_sortedstep.txt` # stepをpriorityの順にソートしたもの

		fo = open("records/#{@session_id}/hoge.xml", "w")
		fo.puts(contents)
		fo.close()
		`cat records/#{@session_id}/hoge.xml | tr -d "\r" | tr -d "\n"  | tr -d "\t" > records/#{@session_id}/#{@session_id}_recipe.xml`

		self.enumerateID
		self.modeLog
	end

	protected

	def enumerateID()
		xml_filename = "records/#{@session_id}/#{@session_id}_recipe.xml"
		output_filename = "records/#{@session_id}/#{@session_id}_table.txt"
		# ファイルの確認
#		if !File.exists?(xml_filename) then
#			errorLog()
#		end

		@doc = REXML::Document.new(open(xml_filename))

		# 属性idを持つelementの名前をキーとするハッシュで，idを列挙
		@doc.get_elements("//*").each{|node|
			if node.attributes.get_attribute("id") != nil then
				if @hash_id.key?("#{node.name}") then
					@hash_id["#{node.name}"]["id"].push(node.attributes.get_attribute("id").value)
				else
					@hash_id["#{node.name}"]["id"] = []
					@hash_id["#{node.name}"]["id"].push(node.attributes.get_attribute("id").value)
				end
			end
		}

		# 列挙したidをjson形式でファイル出力
		open(output_filename, "w"){|io|
#			JSON.dump(@hash_id, io)
			io.puts(JSON.pretty_generate(@hash_id))
		}
	end

	def modeLog()
		hash_mode = Hash.new{|h, k| h[k] = Hash.new(&h.default_proc)}
		sorted_step = []

		if @hash_id.key?("step") then
			@hash_id["step"]["id"].each{|value|
				priority = -1
				@doc.get_elements("//step[@id=\"#{value}\"]").each{|node|
					priority = node.attributes.get_attribute("priority").value.to_i
				}
				hash_mode["step"]["mode"][value] = ["OTHERS","NOT_YET","NOT_CURRENT"]
				sorted_step.push([priority, value])
			}
			sorted_step.sort!{|v1, v2|
				v2[0] <=> v1[0]
			}
		end
		# {element=>"mode"=>{{id=>mode}, {id=>mode}, ...}}
		if @hash_id.key?("substep") then
			@hash_id["substep"]["id"].each{|value|
				hash_mode["substep"]["mode"][value] = ["OTHERS","NOT_YET","NOT_CURRENT"]
			}
		end
		# {element=>"mode"=>{{id=>mode}, {id=>mode}, ...}}
		if @hash_id.key?("audio") then
			@hash_id["audio"]["id"].each{|value|
				hash_mode["audio"]["mode"][value] = ["NOT_YET", -1]
			}
		end
		# {element=>"mode"=>{{id=>mode}, {id=>mode}, ...}}
		if @hash_id.key?("video") then
			@hash_id["video"]["id"].each{|value|
				hash_mode["video"]["mode"][value] = ["NOT_YET", -1]
			}
		end
		# {element=>"mode"=>{{id=>mode}, {id=>mode}, ...}}
		if @hash_id.key?("notification") then
			@hash_id["notification"]["id"].each{|value|
				hash_mode["notification"]["mode"][value] = ["NOT_YET", -1]
			}
		end

		open("records/#{@session_id}/#{@session_id}_mode.txt", "w"){|io|
#			JSON.dump(hash_step, io)
			io.puts(JSON.pretty_generate(hash_mode))
		}
		open("records/#{@session_id}/#{@session_id}_sortedstep.txt", "w"){|io|
			io.puts(JSON.pretty_generate(sorted_step))
		}
	end
end

