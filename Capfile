require "yaml"
CONFIG = YAML.load_file("kowalski.yml")

def bundle_exec(cmd, runit = true)
    command = [
    "source ~/.bash_profile",
    "cd ~/#{CONFIG["project"]}",
    "GEM_HOME=~/.rubygems SUB_ENV=#{CONFIG["code"]} ~/.rubygems/bin/bundle exec #{cmd}"
    ] * " && "

    return command unless runit
    run command, :shell => false
end

def tablog(a, b, c = nil)
    puts "#{a.to_s.rjust(40)} : #{b.to_s.center(16)} : #{c}"
end

def set_status(status, runit = true)
    cmd = "echo \"#{status}\" > ~/.#{CONFIG["project"]}_status"
    runit ? run(cmd) : cmd
end

def alive_hosts
    return @alive_hosts if @alive_hosts

    @alive_hosts = []
    threads = []
    hosts = CONFIG["runners"]["hostnames"]
    hosts = ENV['HOSTS'].split(",") if ENV['HOSTS']
    hosts.each do |host|
        threads << Thread.new do
            if system "ping -c 1 #{host} > /dev/null"
                @alive_hosts << host
            end
        end
    end
    threads.each(&:join)

    puts "Alive runners: #{@alive_hosts * ', '}"
    return @alive_hosts
end

def up_hosts
    return @up_hosts if @up_hosts

    @up_hosts = []
    threads = []
    alive_hosts.each do |host|
        threads << Thread.new do
            netstat = `ssh #{CONFIG["runners"]["user"]}@#{host} 'netstat -nltp 2>/dev/null'`
            if (%w[mysqld searchd mongod redis-server] - netstat.scan(/\d+\/([^\s]+)/).flatten).empty?
                @up_hosts << host
            end
        end
    end
    threads.each(&:join)

    puts "Up runners: #{@up_hosts * ', '}"
    return @up_hosts
end

def run_hooks(hook)
    if CONFIG["master"]["hooks"] && cmd = CONFIG["master"]["hooks"][hook.to_s]
        puts "    [local] #{cmd}"
        system cmd
    end

    if CONFIG["runners"]["hooks"] && cmd = CONFIG["runners"]["hooks"][hook.to_s]
        if cmd =~ /^(thor|rake) /
            bundle_exec cmd
        else
            run cmd
        end
    end
end

def cpu_cores(hostname)
    ssh(hostname, "cat /proc/cpuinfo | grep processor | wc -l").strip.to_i
end

def max_load(hostname)
    ssh(hostname, "cat /proc/loadavg").split[0..2].map(&:to_f).max
end

def ssh(hostname, command)
    return if command.nil? or command == ''
    puts "[#{hostname}] #{command}"
    `ssh #{CONFIG["runners"]["user"]}@#{hostname} '#{command}'`
end

role :alive_hosts, *alive_hosts
role :up_hosts, *up_hosts
set :user, CONFIG["code"]

load 'capistrano/setup'
load 'capistrano/prepare.rb'
load 'capistrano/report.rb'

desc "tears down all services on runners"
task :down do
    set_status "going down..."

    run_hooks :before_down

    git_daemon.down
    spork.down

    bundle_exec "rake kowalski:down"
    bundle_exec "rake mysql:stop"

    run_hooks :after_down

    set_status "down on the ground"
end

desc "brings up all services on runners"
task :up do
    begin
        set_status "getting up..."

        run_hooks :before_up

        update
        run "mkdir -p ~/.redis-temp"

        prepare.sitemaps
        prepare.mysql
        bundle_exec "rake kowalski:up"

        run_hooks :after_up

        set_status "ready to ROCK"
    rescue => e
        puts "#" * 50
        puts "There was an exception:\n\t#{e.inspect}\nInitiating down task...\n\n"
        puts "#" * 50

        down
    end
end

desc "updates #{CONFIG["project"]} (git pull)"
task :update, :roles => :alive_hosts do
    set_status "updating..."

    git_daemon.down
    git_daemon.up

    run_hooks :before_update

    run "cd ~/#{CONFIG["project"]} && git clean -fd"
    run "cd ~/#{CONFIG["project"]} && git checkout -- ."
    run "cd ~/#{CONFIG["project"]} && git fetch origin"
    run "cd ~/#{CONFIG["project"]} && git reset --hard origin/master"

    bundler

    run_hooks :after_update

    git_daemon.down

    set_status "up-to-date"
end

namespace :git_daemon do
    desc "fires up the git daemon for the runners to pull from"
    task :up do
        system "git daemon --base-path=#{CONFIG["master"]["main_path"]} --detach"
        while `netstat -nltp 2> /dev/null | grep git-daemon`.strip == ""
            sleep 0.1
        end
    end

    desc "tears down the git daemon"
    task :down do
        system "killall git-daemon"
    end
end

desc "runs the specs on the runners"
task :run_specs do
    raise "Could not find ready hosts to run the specs on" if roles[:up_hosts].empty?

    spork.down
    run "rm ~/#{CONFIG["project"]}/log/test.log; true"

    @all_files = CONFIG["spec_folders"].map{|f| `find #{CONFIG["master"]["main_path"]}/#{CONFIG["project"]}/spec/#{f}/ -iname "*.rb"`.split("\n")}.flatten

    # Spliting spec files by line count
    @line_counts = `wc -l #{@all_files * ' '}`.split("\n").map do |line|
      line.strip.split.tap{|a| a[0] = a[0].to_i}
    end # => [ [:line_count, :file_path], [:line_count, :file_path]... ]

    # Last element in the array is the total
    total_lines = @line_counts.pop[0]

    @line_counts.map! do |count, file|
        [
            count,
            file.sub(%r[#{CONFIG["master"]["main_path"]}/#{CONFIG["project"]}],
                "/home/#{CONFIG["runners"]["user"]}/#{CONFIG["project"]}")
        ]
    end

    # Sorted by line count descending
    @line_counts = @line_counts.sort_by{|a, _| a}.reverse

    line_step = 0.05 # start with 5%

    lines_left = total_lines
    @sent_files = []
    @received_files = []
    puts "#{@all_files.size} spec_files found"

    hosts = []
    roles[:up_hosts].map(&:host).map do |hostname|
        if CONFIG["parallel"]
            load_avg_cores = begin
                cpu_cores(hostname)/(max_load(hostname)*2)
            rescue ZeroDivisionError
                cpu_cores(hostname)
            end.to_i
            cores_to_use = [1, load_avg_cores, cpu_cores(hostname)-2].sort[1]
            cores_to_use.times {|c| hosts << "#{hostname}.#{c}"}
        else
            hosts << "#{hostname}.0"
        end
    end.flatten

    @threads = []
    shifting = Mutex.new
    putting = Mutex.new
    @errors = 0
    @errors_log = ""

    @progress = Thread.new do
        loop do
            putting.synchronize { tablog "#{@sent_files.size} sent", "MASTER", "#{@received_files.size} received" }
            sleep 5
            break if lines_left == 0
        end
    end

    @timeout = Thread.new do
        sleep 540 # 9 minutes
        putting.synchronize { tablog "Timeout closing in...", "REAPER", nil }

        sleep 60 # 1 minute
        putting.synchronize { tablog "Timeout reached", "REAPER", nil }

        @threads.each(&:kill)
    end

    hosts.each do |host|
        p host
        @threads << Thread.new do
            t = Thread.current
            t[:host] = host
            hostname, core = host.split(".")
            test_env = CONFIG["parallel"] ? "TEST_ENV_NUMBER=#{core} " : ""

            # prepping spork
            spork_port = CONFIG["parallel"] ? 8998 + core.to_i : 8998

            Thread.new do
                spork_up_cmd = "#{test_env}GEM_HOME=~/.rubygems ~/.rubygems/bin/bundle exec spork -p #{spork_port} 1> /dev/null'"
                system "ssh #{CONFIG["runners"]["user"]}@#{hostname} 'source ~/.bash_profile; cd ~/#{CONFIG["project"]}; " + spork_up_cmd
            end

            # renicing the processes
            if CONFIG["runners"]["renice"]
               ssh hostname, "renice #{CONFIG["runners"]["renice"]} -u #{CONFIG["runners"]["user"]}"
            end

            t[:results] = ""
            t[:results] += "\n===============================\n"
            t[:results] += "    Results for #{hostname} (#{core})\n"
            t[:results] += "===============================\n\n"

            t[:specs_and_results] = Hash.new

            loop do
                t[:specs] = shifting.synchronize do
                    # Always get a file
                    if biggest_file_fitting = @line_counts.shift
                        lines_to_send = (lines_left * line_step).to_i - biggest_file_fitting[0]
                        lines_left -= biggest_file_fitting[0]
                        files = [biggest_file_fitting]
                    else
                        files = []
                    end

                    until biggest_file_fitting.nil?
                        biggest_file_fitting = @line_counts.select{|c,_| c <= lines_to_send}.first

                        if biggest_file_fitting
                            @line_counts.reject!{|c| c == biggest_file_fitting}
                            lines_to_send -= biggest_file_fitting[0]
                            lines_left -= biggest_file_fitting[0]

                            files << biggest_file_fitting
                        end
                    end

                    # Only return the file paths
                    files.map{|_,f| f}
                end

                break if t[:specs].empty?

                putting.synchronize { tablog "sending #{t[:specs].size} specs (#{@line_counts.size} left)", "#{hostname}.#{core}" }

                @sent_files += t[:specs]
                cmd = [
                    "source ~/.bash_profile",
                    "cd ~/#{CONFIG["project"]}",
                    set_status("running specs", false),
                    "#{test_env}GEM_HOME=~/.rubygems SUB_ENV=#{CONFIG["code"]} ~/.rubygems/bin/bundle exec rspec --drb --drb-port #{spork_port} --format progress #{t[:specs]*' '} 2>/dev/null"
                ] * ' && '

                result = `ssh #{CONFIG["runners"]["user"]}@#{hostname} '#{cmd}'`
                t[:specs_and_results][t[:specs]] = result
                t[:results] += result

                t[:last_result] = t[:results].split("\n").select{|l| l =~ /\d+ examples?, \d+ failures?/}.last

                unless t[:last_result]
                    @errors += 1
                    @errors_log << t[:results]
                end

                putting.synchronize { tablog nil, "#{hostname}.#{core}", t[:last_result] || 'ERROR' }
                @received_files += t[:specs]
            end

            system "ssh #{CONFIG["runners"]["user"]}@#{hostname} '#{set_status "done running specs", false}'"
            putting.synchronize { tablog "No more specs found", "#{hostname}.#{core}", "Done running specs" }
        end
    end

    # wait for all the spec files to be processed
    Thread.new do
        until shifting.synchronize { @all_files.empty? && @sent_files.size == @received_files.size }
            sleep 0.5
        end

        # some threads might be in limbo (spork not starting), so we kill them
        @threads.each(&:kill)
    end

    @threads.each(&:join)

    all_results = @threads.map{|t| t[:results]}.join
    examples = all_results.scan(/(\d+) examples?/).flatten.map(&:to_i).reduce(&:+)
    failures = all_results.scan(/(\d+) failures?/).flatten.map(&:to_i).reduce(&:+)
    failed_examples = all_results.scan(/^rspec \.\/spec\/.*?$/)

    timestamp = Time.now.strftime('%Y%m%d%H%M')
    results_filename = File.join CONFIG["master"]["main_path"], "logs", "#{timestamp}-results.log"
    require "fileutils"
    FileUtils.mkdir_p File.join(CONFIG["master"]["main_path"], "logs")
    File.open(results_filename, 'w') {|f| f.write(all_results) }

    # Failures have a number prepended like  "3)"
    print "\n\n\n"
    print "Failures:\n\n" + all_results.split("\n\n").select{|b| b =~ /^\s*\d+\)/}.join("\n\n")
    print "Errors:\n\n" + @errors_log + "\n\n"
    print "Failed examples:\n\n" + (failed_examples.sort * "\n") + "\n\n"

    total = "#{examples} examples, #{failures} failures, #{@errors} errors"
    puts "\n  TOTAL:\n  #{total}"
    system "echo '#{Time.now} - #{total}' >> results.log"
    spork.down

    begin
        all_specs_with_results = @threads.inject(Hash.new) do |hash, thread|
            hash.merge thread[:host] => thread[:specs_and_results]
        end

        require "yaml"
        results_filename = File.join CONFIG["master"]["main_path"], "logs", "#{Time.now.to_i}-results-with-specs.yml"
        FileUtils.mkdir_p File.join(CONFIG["master"]["main_path"], "logs")
        File.open(results_filename, 'w') {|f| f.write(all_specs_with_results.to_yaml) }
    rescue
        puts "saving of specs-and-results failed"
    end
end

namespace :spork do
    desc "tears down spork"
    task :down, :roles => :alive_hosts do
        run 'pid="$( ps x | grep spork | grep -v grep | awk \'{print $1}\' )"; if [ "$pid" ]; then kill $pid; else echo "No spork running"; fi'
    end
end

desc "updates gems on the runners (bundle install)"
task :bundler, :roles => :alive_hosts do
    run "source ~/.bash_profile && GEM_HOME=~/.rubygems gem list | grep bundler || GEM_HOME=~/.rubygems gem install bundler -v=1.0.15 --no-ri --no-rdoc", :shell => false
    run "cd ~/#{CONFIG["project"]}; GEM_HOME=~/.rubygems ~/.rubygems/bin/bundle install | grep -v '^Using'", :shell => false
end
