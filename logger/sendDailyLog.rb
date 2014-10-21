#!/usr/bin/ruby

require 'optparse'
require 'date'

require 'rubygems'
require 'mail'

DEFAULT_FROM_ADDRESS = "daily-log@my.hostname.com"
CHAR_SET = "UTF-8"

def isValidAddress(address)
	unless address =~ /^[a-zA-Z0-9_\#!$%&`'*+\-{|}~^\/=?\.]+@[a-zA-Z0-9_\#!$%&`'*+\-{|}~^\/=?\.]+$/ then
		return false
	end
	return true
end


opt = OptionParser.new
mail_to = ""
opt.on('-t','--to [MAIL_ADDRESS]', 'direct "To" header.'){|v|
	if isValidAddress(v) then
		mail_to = v
	else
		STDERR.puts "WARNING: invalid mail address: #{v}"
	end
}

mail_from = DEFAULT_FROM_ADDRESS
opt.on('-f','--from [MAIL_ADDRESS]', 'direct "From" header.'){|v|
	if isValidAddress(v) then
		mail_from = v
	else
		STDERR.puts "WARNING: invalid mail address: #{v}"
	end
}

body = true
opt.on('-a','--attach','flag this option when you want to get the log as attached file.'){|v|
	body = !v
}

storage_priod_day = 30
opt.on('-s','--storage_priod [DAYS]'){|v|
	storage_priod_day = v.to_i
	if storage_priod_day <= 0 then
		STDERR.puts "WARNING: storage_priod is too short. Replace the value to 1 day."
		storage_priod_day = 1
	end
}

$verbose = false
opt.on('-v','--verbose','print all executed command.'){|v|
	$verbose = v
}

opt.parse!(ARGV)

yesterday = Date.today - 1
expiring_day = Date.today - storage_priod_day

def doCommand(command)
	puts command if $verbose
	`#{command}`
end


if ARGV.size < 1 then
	STDERR.puts "USAGE: ruby #{__FILE__} pattern1 pattern2 ... [options]"
	exit 1
end
target_log_files = []
for pattern in ARGV do
	target_log_files += Dir.glob(pattern)
end

mail = Mail.new
mail.from = mail_from
mail.to = mail_to
date = `date +%Y/%m/%d`.strip
mail.subject = "#{ARGV[0]}: #{date}"
mail_body = "No information is logged today"
empty_log_flag = true

for target_log_file in target_log_files do
	next if File.read(target_log_file) == "\n" # 1 for \n added by this script.
	# skip backup files
	next if target_log_file =~ /.*_\d{8}.*/

	if empty_log_flag then
		empty_log_flag = false
		mail_body = ""
	end


	# add yesterday's log to old file, without deleting existant file.
	extname = File.extname(target_log_file)
	dirname = File.dirname(target_log_file)
	basename = File.basename(target_log_file, extname)

	log_file = "#{dirname}/#{basename}_#{yesterday.strftime("%Y%m%d")}#{extname}"
	doCommand("cp #{target_log_file} #{target_log_file}.tmp && echo '' > #{target_log_file}")
	doCommand("cat #{target_log_file}.tmp >> #{log_file}")
	doCommand("rm #{target_log_file}.tmp")

	# delete expired old log files.
	for old_log in Dir.glob("#{target_log_file}.*") do
		next unless old_log =~ /#{dirname}\/#{basename}_(\d{4})(\d{2})(\d{2})/
		date = Date.new($1.to_i,$2.to_i,$3.to_i)
		next if date > expiring_day
		doCommand("rm #{old_log}")
	end

	next if mail_to.empty?
	# add the log to e-mail.
	if body then
		mail_body += "---- #{target_log_file} ----\n"
		mail_body += File.open(log_file).read
		mail_body += "\n\n"
	else
		#doCommand("zip -j #{log_file}.zip #{log_file}")
		#doCommand("rm #{log_file}")
		#mail.add_file("#{log_file}.zip")
		mail.add_file("#{log_file}")
		mail_body = "see attached file"
	end
end

exit 0 if mail_to.empty?
mail.body = mail_body
mail.charset = CHAR_SET
mail.deliver
if $verbose then
	puts mail.to_s
end

if !body then
	for target_log_file in target_log_files do
		next if File.stat(target_log_file).size<=1 # 1 for \n added by this script.
#		log_file = "#{target_log_file}.#{yesterday.strftime("%Y%m%d")}"
#		doCommand("rm #{log_file}.zip")
	end
end
