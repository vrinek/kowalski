namespace :prepare do
    desc "prepares sitemap XMLs"
    task :sitemaps, :roles => :alive_hosts do
        set_status "getting up (sitemaps)"
        bundle_exec "rake sitemap:dummy_sitemaps"
    end

    desc "fires up mongo"
    task :mongo, :roles => :alive_hosts do
        set_status "getting up (mongo)"
        bundle_exec "rake kowalski:mongo:up"
    end

    desc "fires up redis"
    task :redis, :roles => :alive_hosts do
        set_status "getting up (redis)"
        bundle_exec "rake redis:stop redis:start RAILS_ENV=test"
    end

    desc "initializes and fires up sphinx"
    task :sphinx, :roles => :alive_hosts do
        set_status "getting up (sphinx)"

        if CONFIG["parallel"]
            hosts = roles[:alive_hosts].map(&:host)

            host_threads = []
            hosts.each do |hostname|
                host_threads << Thread.new do
                    (cpu_cores(hostname)-2).times do |core|
                        ssh hostname, bundle_exec("rake sphinx:stop RAILS_ENV=test TEST_ENV_NUMBER=#{core}", false)
                        ssh hostname, bundle_exec("rake sphinx:generate_file RAILS_ENV=test TEST_ENV_NUMBER=#{core}", false)
                        ssh hostname, bundle_exec("rake sphinx:index RAILS_ENV=test TEST_ENV_NUMBER=#{core}", false)
                    end
                end
            end

            host_threads.each(&:join)
        else
            bundle_exec "rake kowalski:sphinx:up"
        end
    end

    desc "initializes and fires up mysql on a tmpfs"
    task :mysql, :roles => :alive_hosts do
        set_status "getting up (mysql)"

        run_or_die "cd #{CONFIG["master"]["main_path"]}/#{CONFIG["project"]} && bundle exec rake db:migrate"

        if CONFIG["parallel"]
            hosts = roles[:alive_hosts].map(&:host)

            host_threads = []
            hosts.each do |hostname|
                host_threads << Thread.new do
                    ssh hostname, bundle_exec("rake mysql:stop RAILS_ENV=test", false)
                    ssh hostname, bundle_exec("rake mysql:init_db RAILS_ENV=test", false)
                    ssh hostname, bundle_exec("rake mysql:start RAILS_ENV=test", false)

                    (cpu_cores(hostname)-2).times do |core|
                        ssh hostname, bundle_exec("rake mysql:prepare TEST_ENV_NUMBER=#{core}", false)
                    end
                end
            end

            host_threads.each(&:join)
        else
            bundle_exec "rake mysql:stop mysql:init_db mysql:start RAILS_ENV=test"
            bundle_exec "rake mysql:prepare"
        end
    end
end
