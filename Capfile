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

def set_status(status)
    run "echo '#{status}' > ~/.#{CONFIG["project"]}_status"
end

def alive_hosts
    hosts = CONFIG["runners"]["hostnames"].select do |host|
        system "ping -c 1 #{host} > /dev/null"
    end

    puts "\nAlive runners: #{hosts * ', '}\n\n"
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

def ssh(hostname, command)
    return if command.nil? or command == ''
    puts "[#{hostname}] #{command}"
    `ssh #{CONFIG["runners"]["user"]}@#{hostname} '#{command}'`
end

role :alive_hosts, *alive_hosts
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
    bundle_exec "rake redis:stop RAILS_ENV=test"

    run_hooks :after_down

    set_status "down on the ground"
end

desc "brings up all services on runners"
task :up do
    set_status "getting up..."

    run_hooks :before_up

    update
    run "mkdir -p ~/.redis-temp"

    bundler
    prepare.sitemaps
    prepare.mongo
    prepare.redis
    prepare.mysql
    prepare.sphinx

    run_hooks :after_up

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
    run "cd ~/#{CONFIG["project"]} && git submodule update"
    run "cd ~/#{CONFIG["project"]} && git reset --hard master"

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
    spork.down

    @all_files = CONFIG["spec_folders"].map{|f| `find #{CONFIG["master"]["main_path"]}/#{CONFIG["project"]}/spec/#{f}/ -iname "*.rb"`.split("\n")}.flatten
    @all_files.map! do |file|
        file.sub(%r[#{CONFIG["master"]["main_path"]}/#{CONFIG["project"]}], "/home/#{CONFIG["runners"]["user"]}/#{CONFIG["project"]}")
    end
    puts "#{@all_files.size} spec_files found"

    hosts = roles[:alive_hosts].map(&:host)
    @threads = []
    batch_size = lambda { [1, @all_files.size/(hosts.size**1.5).to_i, 20].sort[1] }
    shifting = Mutex.new
    putting = Mutex.new
    @errors = 0

    hosts.each do |host|
        @threads << Thread.new do
            t = Thread.current
            hostname = host.dup

            Thread.new do
                system "ssh #{CONFIG["runners"]["user"]}@#{hostname} 'source ~/.bash_profile; cd ~/#{CONFIG["project"]}; GEM_HOME=~/.rubygems ~/.rubygems/bin/bundle exec spork -p 8998 1> /dev/null'"
            end

            until t[:spork_is_up]
                sleep 0.1
                t[:spork_is_up] = (`ssh #{CONFIG["runners"]["user"]}@#{hostname} "netstat -nl | grep 8998"`.strip != "")
            end

            t[:results] = ""
            t[:results] += "\n===============================\n"
            t[:results] += "    Results for #{hostname}\n"
            t[:results] += "===============================\n\n"

            until (t[:specs] = shifting.synchronize { @all_files.shift(batch_size.call) * ' ' }).empty?
                putting.synchronize { tablog "sending #{t[:specs].split.size} specs (#{@all_files.size} left)", hostname }
                cmd = [
                    "source ~/.bash_profile",
                    "cd ~/#{CONFIG["project"]}",
                    "GEM_HOME=~/.rubygems SUB_ENV=#{CONFIG["code"]} ~/.rubygems/bin/bundle exec rspec --drb --drb-port 8998 --format progress #{t[:specs]} 2>/dev/null"
                ] * ' && '
                t[:results] += `ssh #{CONFIG["runners"]["user"]}@#{host} '#{cmd}'`
                @errors += 1 unless t[:results].split("\n").last =~ /\d+ examples?, \d+ failures?/
                putting.synchronize { tablog nil, hostname, "#{t[:results].split("\n").last}" }
            end
        end
    end

    @threads.each(&:join)
    all_results = @threads.map{|t| t[:results]}
    examples = all_results.join.scan(/(\d+) examples?/).flatten.map(&:to_i).reduce(&:+)
    failures = all_results.join.scan(/(\d+) failures?/).flatten.map(&:to_i).reduce(&:+)

    puts all_results.join

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
