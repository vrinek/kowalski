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
    puts "#{a.to_s.rjust(40)} : #{b.to_s.center(12)} : #{c}"
end

def set_status(status, runit = true)
    cmd = "echo \"#{status}\" > ~/.#{CONFIG["project"]}_status"
    runit ? run cmd : cmd
end

def alive_hosts
    hosts = CONFIG["runners"]["hostnames"].select do |host|
        system "ping -c 1 #{host} > /dev/null"    end

    puts "Alive runners: #{hosts * ', '}"
    return hosts
end

def up_hosts
    hosts = alive_hosts.select do |host|
        netstat = `ssh #{CONFIG["runners"]["user"]}@#{host} 'netstat -nltp 2>/dev/null'`
        (%w[mysqld searchd mongod redis-server] - netstat.scan(/\d+\/([^\s]+)/).flatten).empty?
    end

    puts "Up runners: #{hosts * ', '}"
    return hosts
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
    bundle_exec "rake sphinx:stop RAILS_ENV=test"
    bundle_exec "rake mysql:stop"
    bundle_exec "rake mongo:stop RAILS_ENV=test"
    bundle_exec "rake redis:stop RAILS_ENV=test; true" # usually fails

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
        prepare.mongo
        prepare.redis
        prepare.mysql
        prepare.sphinx

        run_hooks :after_up
    rescue => e
        puts "There was an exception:\n\t#{e.inspect}\nInitiating down task...\n\n"
        down
    end

    set_status "ready to ROCK"
end

desc "updates #{CONFIG["project"]} (git pull)"
task :update, :roles => :alive_hosts do
    set_status "updating..."

    git_daemon.down
    git_daemon.up

    run_hooks :before_update

    run "cd ~/#{CONFIG["project"]} && git clean -f"
    run "cd ~/#{CONFIG["project"]} && git checkout -- ."
    run "cd ~/#{CONFIG["project"]} && git reset --hard HEAD"
    run "cd ~/#{CONFIG["project"]} && git checkout master"
    run "cd ~/#{CONFIG["project"]} && git pull --rebase"
    run "cd ~/#{CONFIG["project"]} && git submodule init"
    run "cd ~/#{CONFIG["project"]} && git submodule update"
    run "cd ~/#{CONFIG["project"]} && git reset --hard master"

    bundler

    run_hooks :after_update

    git_daemon.down

    set_status "up-to-date"
end

namespace :git_daemon do
    desc "fires up the git daemon for the runners to pull from"
    task :up do
        system "git daemon --base-path=#{CONFIG["master"]["main_path"]} --detach"
        while `pgrep git-daemon`.strip == ""
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

    @all_files = CONFIG["spec_folders"].map{|f| `find #{CONFIG["master"]["main_path"]}/#{CONFIG["project"]}/spec/#{f}/ -iname "*.rb"`.split("\n")}.flatten
    @all_files.map! do |file|
        file.sub(%r[#{CONFIG["master"]["main_path"]}/#{CONFIG["project"]}], "/home/#{CONFIG["runners"]["user"]}/#{CONFIG["project"]}")
    end
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
    starting_batch = @all_files.size/(hosts.size**CONFIG["load_balance_start"].to_f).to_i
    batch_size = lambda { [1, @all_files.size/(hosts.size).to_i, starting_batch].sort[1] }
    shifting = Mutex.new
    putting = Mutex.new
    @errors = 0
    @errors_log = ""

    @progress = Thread.new do
        loop do
            putting.synchronize { tablog "#{@sent_files.size} sent", "MASTER", "#{@received_files.size} received" }
            sleep 5
            break if @all_files.empty?
        end
    end

    hosts.each do |host|
        p host
        @threads << Thread.new do
            t = Thread.current
            hostname, core = host.split(".")
            test_env = CONFIG["parallel"] ? "TEST_ENV_NUMBER=#{core} " : ""

            # prepping spork
            spork_port = CONFIG["parallel"] ? 8998 + core.to_i : 8998

            Thread.new do
                spork_up_cmd = "#{test_env}GEM_HOME=~/.rubygems ~/.rubygems/bin/bundle exec spork -p #{spork_port} 1> /dev/null'"
                system "ssh #{CONFIG["runners"]["user"]}@#{hostname} 'source ~/.bash_profile; cd ~/#{CONFIG["project"]}; " + spork_up_cmd
            end

            until (`ssh #{CONFIG["runners"]["user"]}@#{hostname} "netstat -nl | grep #{spork_port}"`.strip != "")
                sleep 0.1
                raise "Spork has disappeared" unless system("ssh #{CONFIG["runners"]["user"]}@#{hostname} \"pgrep -f spork -u #{CONFIG["runners"]["user"]} 1>/dev/null\"")
            end
            # spork is up

            # renicing the processes
            if CONFIG["runners"]["renice"]
               ssh hostname, "renice #{CONFIG["runners"]["renice"]} -u #{CONFIG["runners"]["user"]}"
            end

            t[:results] = ""
            t[:results] += "\n===============================\n"
            t[:results] += "    Results for #{hostname} (#{core})\n"
            t[:results] += "===============================\n\n"

            loop do
                t[:specs] = shifting.synchronize { @all_files.shift(batch_size.call) }
                break if t[:specs].empty?

                putting.synchronize { tablog "sending #{t[:specs].size} specs (#{@all_files.size} left)", "#{hostname}.#{core}" }

                @sent_files += t[:specs]
                cmd = [
                    "source ~/.bash_profile",
                    "cd ~/#{CONFIG["project"]}",
                    set_status("running specs", false),
                    "#{test_env}GEM_HOME=~/.rubygems SUB_ENV=#{CONFIG["code"]} ~/.rubygems/bin/bundle exec rspec --drb --drb-port #{spork_port} --format progress #{t[:specs]*' '} 2>/dev/null"
                ] * ' && '
                t[:results] += `ssh #{CONFIG["runners"]["user"]}@#{hostname} '#{cmd}'`
                unless t[:results].split("\n").last =~ /\d+ examples?, \d+ failures?/
                    @errors += 1
                    @errors_log << t[:results]
                end
                putting.synchronize { tablog nil, "#{hostname}.#{core}", "#{t[:results].split("\n").last}" }
                @received_files += t[:specs]
            end

            system "ssh #{CONFIG["runners"]["user"]}@#{hostname} '#{set_status "done running specs"}'"
        end
    end

    @threads.each(&:join)
    all_results = @threads.map{|t| t[:results]}.join
    examples = all_results.scan(/(\d+) examples?/).flatten.map(&:to_i).reduce(&:+)
    failures = all_results.scan(/(\d+) failures?/).flatten.map(&:to_i).reduce(&:+)

    results_filename = File.join CONFIG["master"]["main_path"], "logs", "#{Time.now.to_i}-results.log"
    require "fileutils"
    FileUtils.mkdir_p File.join(CONFIG["master"]["main_path"], "logs")
    File.open(results_filename, 'w') {|f| f.write(all_results) }

    # Failures have a number prepended like  "3)"
    puts "Failures:\n\n" + all_results.split("\n\n").select{|b| b =~ /^\s*\d+\)/}.join("\n\n")

    puts "Errors:\n\n" + @errors_log + "\n\n"

    total = "#{examples} examples, #{failures} failures, #{@errors} errors"
    puts "\n  TOTAL:\n  #{total}"
    system "echo '#{Time.now} - #{total}' >> results.log"
    spork.down
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
