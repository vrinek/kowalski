require "rubygems"
require "sinatra"
require "yaml"
CONFIG = YAML.load_file("kowalski.yml")

get '/' do
	"<p>do a \"GET /#{CONFIG["project"]}/:task\" to initiate a capistrano task</p>" +
	"<p>\"GET /#{CONFIG["project"]}/:task.raw\" will render a stream with the output</p>"
end

get "/#{CONFIG["project"]}/:task" do |task|
	cmd, format = task.split(".")
	time = Time.now
	system "mkdir -p #{CONFIG["master"]["main_path"]}/logs"
	filename = "#{CONFIG["master"]["main_path"]}/logs/#{time.to_i}-#{cmd}.txt"

	case format
	when 'raw'
		content_type :txt
		IO.popen "cap #{cmd} 2>&1 | tee #{filename}"
	else
		system "cap #{cmd} > #{filename} 2>&1"
		system "cp #{filename} #{CONFIG["master"]["main_path"]}/logs/latest-#{cmd}.txt"

		output = `cat #{filename} | sed -r "s/\\x1B\\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g"`
		output.gsub!(/>/, '&gt;')
		output.gsub!(/</, '&lt;')

		html = '<table style="width:100%">'
		html << '<thead><tr>'
		hosts = output[/Alive runners: (.*?)\n/, 1].split(", ")
		hosts.each do |host|
			html << "<th>#{host}</th>"
		end
		html << '</tr></thead><tbody>'

		host_lines = {}
		output.split("\n").each do |line|
			unless line =~ /^[\s\*]+\[[^\]]+\]/
				html << "<tr>\n"
				hosts.each do |host|
					html << "<td><pre>#{(host_lines[host] || []) * "</br>"}</pre></td>\n"
				end
				html << "</tr>\n"
				host_lines = {}
				html << "<tr><td style=\"color:#999\" colspan=\"#{hosts.size}\"><pre>#{line}</pre></td></tr>\n"
			else
				hostname = line[/(#{hosts * '|'})/, 1]
				host_lines[hostname] ||= []
				host_lines[hostname] << line.strip.gsub(/^[\s\*]*\[[^\]]+\]/, '').strip
			end
		end

		html << "</tbody></table>"
		"<p>Done in #{Time.now - time} seconds</p>" +
		"<p><small><pre>#{filename}</pre></small></p>" +
		"<br /><br />" + html
	end

end
