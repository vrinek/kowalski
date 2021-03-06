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

        # silences MOTD message
        run "touch ~/.hushlogin"
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

    desc "sets up elasticsearch"
    task :elastic, :roles => :alive_hosts do
        raise "There are no instructions for elasticsearch install in kowalski.yml" if CONFIG["services"]["elastic"].nil? or CONFIG["services"]["elastic"]["install"].empty?

        install_elastic = ([
            "mkdir -p /home/#{CONFIG["runners"]["user"]}/src",
            "mkdir -p /home/#{CONFIG["runners"]["user"]}/bin",
            "rm -rf /home/#{CONFIG["runners"]["user"]}/src/elasticsearch*",
            "cd /home/#{CONFIG["runners"]["user"]}/src"
        ] + CONFIG["services"]["elastic"]["install"] + [
            "echo 'export PATH=\"/home/#{CONFIG["runners"]["user"]}/#{CONFIG["services"]["elastic"]["bin_path"]}:$PATH\"' >> ~/.bash_profile"
        ]) * " && "

        cmd = ''
        cmd << "source /home/#{CONFIG["runners"]["user"]}/.bash_profile && "
        cmd << 'if [ "$( elasticsearch -v | grep \''+CONFIG["services"]["elastic"]["version"].gsub(/\./, "\\.")+'\' )" ]; '
        cmd <<     'then echo "elasticsearch is OK"; '
        cmd <<     "else #{install_elastic}; "
        cmd << 'fi'

        run cmd, :shell => false

        if CONFIG["services"]["elastic"]["plugins"]
            cmd = CONFIG["services"]["elastic"]["plugins"].map do |plugin|
                "/home/#{CONFIG["runners"]["user"]}/elastic/bin/plugin -install #{plugin}"
            end * ' && '

            run cmd, :shell => false
        end
    end

    desc "sets up redis 2.4.2"
    task :redis, :roles => :alive_hosts do
        raise "There are no instructions for redis install in kowalski.yml" if CONFIG["services"]["redis"].nil? or CONFIG["services"]["redis"]["install"].empty?

        install_redis = ([
            "mkdir -p /home/#{CONFIG["runners"]["user"]}/src",
            "mkdir -p /home/#{CONFIG["runners"]["user"]}/bin",
            "rm -rf /home/#{CONFIG["runners"]["user"]}/src/redis-*",
            "cd /home/#{CONFIG["runners"]["user"]}/src"
        ] + CONFIG["services"]["redis"]["install"] + [
            "echo 'export PATH=\"/home/#{CONFIG["runners"]["user"]}/bin:$PATH\"' >> ~/.bash_profile"
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

    desc "sets up nodejs"
    task :nodejs, :roles => :alive_hosts do
        if CONFIG["services"]["nodejs"].nil? or CONFIG["services"]["nodejs"]["install"].empty?
            raise "There are no instructions for nodejs install in kowalski.yml"
        end

        path_line = "PATH=\"/home/#{CONFIG["runners"]["user"]}/#{CONFIG["services"]["nodejs"]["bin_path"]}/:$PATH\""

        install_nodejs = ([
            "mkdir -p /home/#{CONFIG["runners"]["user"]}/src",
            "rm -rf /home/#{CONFIG["runners"]["user"]}/src/nodejs",
            "cd /home/#{CONFIG["runners"]["user"]}/src"
        ] + CONFIG["services"]["nodejs"]["install"] + [
            "echo 'export #{path_line}' >> ~/.bash_profile"
        ]) * " && "

        version_rx = CONFIG["services"]["nodejs"]["version"].gsub(/\./, "\\.")

        cmd = ''
        cmd << "source /home/#{CONFIG["runners"]["user"]}/.bash_profile && "
        cmd << 'if [ "$( node -v | grep \''+version_rx+'\' )" ]; '
        cmd <<     'then echo "nodejs is OK"; '
        cmd <<     "else #{install_nodejs}; "
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
        elastic
        project
        tmpfs
    end

    namespace :nuke do
        task :all do
            run "rm -rf ~/*"
            run "rm -rf ~/.rbenv"
            run "rm -rf ~/.bash_profile"
            run "rm -rf ~/.bash_rc"
            run "rm -rf ~/.gems"
            run "rm -rf ~/.profile"
            run "rm -rf ~/.redis-temp"
            run "rm -rf ~/.rubygems"
            run "rm -rf ~/.#{CONFIG["project"]}_status"
        end

        task :project do
            run "rm -rf ~/#{CONFIG["project"]}/"
        end
    end
end
