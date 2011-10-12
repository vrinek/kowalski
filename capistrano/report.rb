desc "reports the status of the services"
task :status do
    run "cat ~/.#{CONFIG["project"]}_status"

    %w[mysqld searchd mongod redis-server].each do |service|
        run "if [ \"$( netstat -nltp 2>/dev/null | grep #{service} )\" ]; then echo \"#{service} is up\"; else echo \"#{service} is down\"; fi"
    end
end


desc "reports versions and last commit"
task :report, :roles => :alive_hosts do
    {
        "ruby --version" => ["1.8.7", "patchlevel 352"],
        "searchd --help | head -1" => ["0.9.9"],
        "mongod --version | head -1" => ["1.6.5"],
        "redis-server --version" => ["2.1.5.sinit"]
    }.each do |command, version|
        cmd = " if [ \"$( #{command} | grep '#{version.map{|p| p.gsub(/\./, "\\.")} * '.*'}' )\" ]; "
        cmd += "then echo \"#{command.split.first} is OK\" ; else echo \"WARNING: should have version #{version * ' '} ($(#{command}))\"; fi "
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
