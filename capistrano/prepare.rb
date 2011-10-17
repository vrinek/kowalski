namespace :prepare do
    desc "prepares sitemap XMLs"
    task :sitemaps, :roles => :alive_hosts do
        set_status "getting up (sitemaps)"
        bundle_exec "rake sitemap:dummy_sitemaps"
    end

    desc "fires up mongo"
    task :mongo, :roles => :alive_hosts do
        set_status "getting up (mongo)"
        bundle_exec "rake mongo:stop RAILS_ENV=test"
        bundle_exec "rake mongo:start RAILS_ENV=test"
    end

    desc "fires up redis"
    task :redis, :roles => :alive_hosts do
        set_status "getting up (redis)"
        bundle_exec "rake redis:stop RAILS_ENV=test"
        bundle_exec "rake redis:start RAILS_ENV=test"
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
            bundle_exec "rake sphinx:stop RAILS_ENV=test"
            bundle_exec "rake sphinx:generate_file RAILS_ENV=test"
            bundle_exec "rake sphinx:index RAILS_ENV=test"
        end
    end

    desc "initializes and fires up mysql on a tmpfs"
    task :mysql, :roles => :alive_hosts do
        set_status "getting up (mysql)"

        hosts = roles[:alive_hosts].map(&:host)

        host_threads = []
        hosts.each do |hostname|
            host_threads << Thread.new do
                ssh hostname, bundle_exec("rake mysql:stop RAILS_ENV=test", false)
                ssh hostname, bundle_exec("rake mysql:init_db RAILS_ENV=test", false)
                ssh hostname, bundle_exec("rake mysql:start RAILS_ENV=test", false)

                if CONFIG["parallel"]
                    (cpu_cores(hostname)-2).times do |core|
                        ssh hostname, bundle_exec("rake mysql:prepare TEST_ENV_NUMBER=#{core}", false)
                    end
                else
                    ssh hostname, bundle_exec("rake mysql:prepare", false)
                end
            end
        end

        host_threads.each(&:join)
    end
end
