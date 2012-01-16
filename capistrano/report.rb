desc "reports the status of the services"
task :status do
    run "cat ~/.#{CONFIG["project"]}_status"

    cmd = %w[mysqld searchd mongod redis-server].map do |service|
        "if [ \"$( netstat -nltp 2>/dev/null | grep #{service} )\" ]; then echo -e \"\\e[32m#{service} is up\\e[0m\"; else echo -e \"\\e[31m#{service} is down\\e[0m\"; fi"
    end.join('; ')

    cmd << "; if [ \"$( netstat -nltp 2>/dev/null | grep \" $( pgrep -f spork -u #{CONFIG["runners"]["user"]} )/ruby\" )\" ]; then echo -e \"\\e[32mspork is up\\e[0m\"; else echo -e \"\\e[31mspork is down\\e[0m\"; fi"

    run cmd, :shell => false
end


desc "reports versions and last commit"
task :report, :roles => :alive_hosts do
    {
        "ruby --version" => "1.9.3p0",
        "searchd --help | head -1" => [CONFIG["services"]["sphinx"]["version"]],
        "mongod --version | head -1" => [CONFIG["services"]["mongo"]["version"]],
        "redis-server --version" => [CONFIG["services"]["redis"]["version"]]
    }.each do |command, version|
        cmd = " if [ \"$( #{command} | grep '#{version.map{|p| p.gsub(/\./, "\\.")} * '.*'}' )\" ]; "
        cmd += "then echo -e \"\\e[32m#{command.split.first} is OK\\e[0m\" ; else echo -e \"\\e[31mWARNING: should have version #{version * ' '} ($(#{command}))\\e[0m\"; fi "
        run "source ~/.bash_profile && #{cmd} ; true", :shell => false
    end

    run "git --version"
    run "cd ~/#{CONFIG["project"]} && git clean -n -d"
    run "cd ~/#{CONFIG["project"]} && git status --short"
    run "cd #{CONFIG["project"]} && git log -1"
    run "df -h; true"
    run "du -sh ~"

    run "netstat -nltp 2>/dev/null | grep -v '\\- *$' | grep '^tcp' | awk '{print $4, $7}' | sort"
end

task :disk_space do
    run "df -h; true"
    run "du -sh ~"
    run "du -sh ~/*"
    run "du -sh ~/#{CONFIG["project"]}/*"
    run "du -sh ~/#{CONFIG["project"]}/tmp/*"
end

task :cpuload do
    run "ps -U #{CONFIG["runners"]["user"]} -o pcpu --no-headers | awk '{sum+=$1} END{print sum}'"
end
