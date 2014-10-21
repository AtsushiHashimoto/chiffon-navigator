#!/usr/bin/ruby

require 'date'

if ARGV.size < 1
	STDERR.puts "Usage: ruby #{__FILE__} chiffon.log"
end

$time_format = /(\d{4})\.(\d{2})\.(\d{2})_(\d{2})\.(\d{2})\.(\d{2})\.(\d{6})/
def parse(str)
	return nil if nil == (str =~ $time_format)
	return Time.gm($1.to_i,$2.to_i,$3.to_i,$4.to_i,$5.to_i,$6.to_i,$7.to_i)
end
def parse_content(str)
	str =~ /.*\((.+?)-(.+?)\).*/
	user_id = $1
	return nil, str if user_id == nil
	time = $2
	return nil, str if nil == (time =~ $time_format)
	return "#{user_id}-#{time}", str
end


logfile = ARGV[0]
log_format = /\[(.*)\]\s*\[(.*)\]\s*\[(.*)\]\s*(.*)/
log_format_start = /\[(.*)\]\s*\[(.*)\]\s*(.*)/

log = {:content=>""}

log_dir = File.dirname(logfile)
output_file_prefix = File.basename(logfile,File.extname(logfile))

sessionlogs = {}

File.open(logfile).each{|line|
	#puts line
	if nil != (line =~ log_format) then
		# dump buffered info
		if !log.empty? then
			if nil != log[:session_id] then
				session_id = log[:session_id]
				sessionlogs[session_id] = [] if !sessionlogs.include?(session_id)
				sessionlogs[session_id] << log
			end
		end

		# restart to buffer info
		time = parse($1)
		level = $2
		type = $3
		session_id, content = parse_content($4)
		log = {:time=>time,:level=>level,:type=>type,:session_id=>session_id, :content=>content}
	elsif nil != (line=~ log_format_start) then
		next
	else
		log[:content] += line
	end
}
:w

def print(log)
	return log if log.class.to_s == "String"

	return "[#{log[:time]}] [#{log[:level]}] [#{log[:type]}] #{log[:content]}"
end

for session_id,logs in sessionlogs do
	out = File.open("#{log_dir}/#{session_id}.#{output_file_prefix}.log","w")
	for log in logs do
		out.puts print(log)
	end
	out.close
end
