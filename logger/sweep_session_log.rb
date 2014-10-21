#!/usr/bin/ruby

if ARGV.size < 1 then
	$stderr.puts "USAGE: ruby #{__FILE__} target_dir"
	exit 1
end

TAR_DIR = ARGV[0]
UNSWEEPED_FILES = ["#{TAR_DIR}/development.log","#{TAR_DIR}/production.log"]

for file in Dir.glob("#{TAR_DIR}/*") do
	next if UNSWEEPED_FILES.include?(file)
	next if File.read(file)!="\n"
	command = "rm #{file}"
	puts command
	`#{command}`
end
