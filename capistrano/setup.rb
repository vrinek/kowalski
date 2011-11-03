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
        upload "scripts/setup_ruby.sh", "prepare/setup_ruby.sh", :mode => "+x", :via => :scp
        run "~/prepare/setup_ruby.sh", :shell => false
    end

    task :gems, :roles => :alive_hosts do
        {
            :bundler => '1.0.15'
        }.each do |gem_name, gem_version|
            run "source ~/.bash_profile && GEM_HOME=~/.rubygems gem list | grep #{gem_name} | grep #{gem_version} || GEM_HOME=~/.rubygems gem install #{gem_name} -v=#{gem_version} --no-ri --no-rdoc", :shell => false
        end
    end

    desc "sets up tmpfs for mysql"
    task :tmpfs, :roles => :alive_hosts do
        run "mkdir -p ~/prepare"
        run "rm -f ~/prepare/setup_tmpfs.sh"
        upload "scripts/setup_tmpfs.sh", "prepare/setup_tmpfs.sh", :mode => "+x", :via => :scp
        run "~/prepare/setup_tmpfs.sh", :shell => false
    end

    desc "sets up redis 2.1.5.sinit"
    task :redis, :roles => :alive_hosts do
        raise "There are no instructions for redis install in kowalski.yml" if CONFIG["services"]["redis"].nil? or CONFIG["services"]["redis"]["install"].empty?

        install_redis = ([
            "mkdir -p /home/#{CONFIG["runners"]["user"]}/src",
            "rm -rf /home/#{CONFIG["runners"]["user"]}/src/redis-sinit",
            "cd /home/#{CONFIG["runners"]["user"]}/src"
        ] + CONFIG["services"]["redis"]["install"] + [
            "echo 'export PATH=\"/home/#{CONFIG["runners"]["user"]}/src/redis-sinit/src/:$PATH\"' >> ~/.bash_profile"
        ]) * " && "

        cmd = ''
        cmd << "source /home/#{CONFIG["runners"]["user"]}/.bash_profile && "
        cmd << 'if [ "$( redis-server --version | grep \''+CONFIG["services"]["redis"]["version"].gsub(/\./, "\\.")+'\' )" ]; '
        cmd <<     'then echo "redis is OK"; '
        cmd <<     "else #{install_redis}; "
        cmd << 'fi'

        run cmd, :shell => false
    end

    desc "sets up mongo 1.6.5"
    task :mongo, :roles => :alive_hosts do
        raise "There are no instructions for mongo install in kowalski.yml" if CONFIG["services"]["mongo"].nil? or CONFIG["services"]["mongo"]["install"].empty?

        install_mongo = ([
            "mkdir -p /home/#{CONFIG["runners"]["user"]}/src",
            "rm -rf /home/#{CONFIG["runners"]["user"]}/src/mongo",
            "cd /home/#{CONFIG["runners"]["user"]}/src"
        ] + CONFIG["services"]["mongo"]["install"] + [
            "echo 'export PATH=\"/home/#{CONFIG["runners"]["user"]}/src/mongo/bin/:$PATH\"' >> ~/.bash_profile"
        ]) * " && "

        cmd = ''
        cmd << "source /home/#{CONFIG["runners"]["user"]}/.bash_profile && "
        cmd << 'if [ "$( mongod --version | grep \''+CONFIG["services"]["mongo"]["version"].gsub(/\./, "\\.")+'\' )" ]; '
        cmd <<     'then echo "mongo is OK"; '
        cmd <<     "else #{install_mongo}; "
        cmd << 'fi'

        run cmd, :shell => false
    end

    desc "sets up sphinx-0.9.9"
    task :sphinx, :roles => :alive_hosts do
        raise "There are no instructions for sphinx install in kowalski.yml" if CONFIG["services"]["sphinx"].nil? or CONFIG["services"]["sphinx"]["install"].empty?

        install_sphinx = ([
            "mkdir -p /home/#{CONFIG["runners"]["user"]}/src",
            "rm -rf /home/#{CONFIG["runners"]["user"]}/src/sphinx",
            "cd /home/#{CONFIG["runners"]["user"]}/src"
        ] + CONFIG["services"]["sphinx"]["install"] + [
            "echo 'export PATH=\"/home/#{CONFIG["runners"]["user"]}/src/sphinx-bin/:$PATH\"' >> ~/.bash_profile"
        ]) * " && "

        cmd = ''
        cmd << "source /home/#{CONFIG["runners"]["user"]}/.bash_profile && "
        cmd << 'if [ "$( searchd --h | head -1 | grep \''+CONFIG["services"]["sphinx"]["version"].gsub(/\./, "\\.")+'\' )" ]; '
        cmd <<     'then echo "sphinx is OK"; '
        cmd <<     "else #{install_sphinx}; "
        cmd << 'fi'

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
        gems
        redis
        mongo
        project
        tmpfs
    end
end
