#!/usr/bin/ruby

require 'rubygems'
require 'json'

def searchElementName(session_id, id)
	hash_id = Hash.new()
	open("records/#{session_id}/#{session_id}_table.txt", "r"){|io|
		hash_id = JSON.load(io)
	}
	element_name = nil
	hash_id.each{|key1, value1|
		value1["id"].each{|value2|
			if value2 == id then
				element_name = key1
				break
			end
		}
	}
	return element_name
end

def logger()
end

def errorLOG()
end
