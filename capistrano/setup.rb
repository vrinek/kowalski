namespace :setup do
    desc "sets up SSH authorization"
    task :ssh do
        roles[:alive_hosts].map(&:host).each do |host|
            puts "    Setting up SSH on \"#{host}\""

            if system("ping -c 1 #{host} > /dev/null")
                unless system("ssh #{CONFIG["runners"]["user"]}@#{host} -o PasswordAuthentication=no 'echo \"    - Already authorized\"'")
                    puts "    Setting up SSH authentication"

                    system "ssh #{CONFIG["runners"]["user"]}@#{host} mkdir -p .ssh"
                    system "cat ~/.ssh/id_rsa.pub | ssh #{CONFIG["runners"]["user"]}@#{host} 'cat >> .ssh/authorized_keys'"
                end
            else
                puts "    Ping to \"#{host}\" failed"
            end
        end
    end

    desc "sets up ruby using rbenv and ruby-build"
    task :ruby, :roles => :alive_hosts do
        run "mkdir -p ~/prepare"
        run "rm -f ~/prepare/setup_ruby.sh"
        upload "script/distributed/setup_ruby.sh", "prepare/setup_ruby.sh", :mode => "+x", :via => :scp
        run "~/prepare/setup_ruby.sh", :shell => false
    end

    desc "sets up redis 2.1.5.sinit"
    task :redis, :roles => :alive_hosts do
        install_redis = [
            "mkdir -p /home/#{CONFIG["runners"]["user"]}/src",
            "rm -rf /home/#{CONFIG["runners"]["user"]}/src/redis-sinit",
            "git clone git://github.com/ctrochalakis/redis-sinit.git /home/#{CONFIG["runners"]["user"]}/src/redis-sinit",
            "cd /home/#{CONFIG["runners"]["user"]}/src/redis-sinit",
            "make",
            "echo 'export PATH=\"/home/#{CONFIG["runners"]["user"]}/src/redis-sinit/src/:$PATH\"' >> ~/.bash_profile"
        ] * " && "

        cmd =  "source /home/#{CONFIG["runners"]["user"]}/.bash_profile && "
        cmd += 'if [ "$( redis-server --version | grep \'2\\.1\\.5\\.sinit\' )" ]; '
        cmd +=     'then echo "redis is OK"; '
        cmd +=     "else #{install_redis}; "
        cmd += 'fi'

        run cmd, :shell => false
    end

    desc "sets up mongo 1.6.5"
    task :mongo, :roles => :alive_hosts do
        install_mongo = [
            "mkdir -p /home/#{CONFIG["runners"]["user"]}/src",
            "rm -rf /home/#{CONFIG["runners"]["user"]}/src/mongo",
            "cd /home/#{CONFIG["runners"]["user"]}/src",
            "curl -s http://downloads.mongodb.org/linux/mongodb-linux-i686-static-1.6.5.tgz > mongo.tgz",
            "tar zxf mongo.tgz",
            "rm mongo.tgz",
            "mv mongodb-linux-i686-static-1.6.5 mongo",
            "echo 'export PATH=\"/home/#{CONFIG["runners"]["user"]}/src/mongo/bin/:$PATH\"' >> ~/.bash_profile"
        ] * " && "

        cmd =  "source /home/#{CONFIG["runners"]["user"]}/.bash_profile && "
        cmd += 'if [ "$( mongod --version | grep \'1\\.6\\.5\' )" ]; '
        cmd +=     'then echo "mongo is OK"; '
        cmd +=     "else #{install_mongo}; "
        cmd += 'fi'

        run cmd, :shell => false
    end

    desc "clone #{CONFIG["project"]} from #{CONFIG["git_clone"]}"
    task :project, :roles => :alive_hosts do
        git_daemon.up
        run "ls #{CONFIG["project"]}/.git || git clone #{CONFIG["git_clone"]}; true"
        git_daemon.down

        run "cd ~/#{CONFIG["project"]} && git config user.email \"#{CONFIG["code"]}@nowhere.com\""
        run "cd ~/#{CONFIG["project"]} && git config user.name \"#{CONFIG["code"]} Runner\""
    end

    task :all do
        ssh
        ruby
        redis
        mongo
        project
    end
end
