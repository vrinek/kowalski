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
        bundle_exec "rake sphinx:stop RAILS_ENV=test"
        bundle_exec "rake sphinx:generate_file RAILS_ENV=test"
        bundle_exec "rake sphinx:index RAILS_ENV=test"
    end

    desc "initializes and fires up mysql on a tmpfs"
    task :mysql, :roles => :alive_hosts do
        set_status "getting up (mysql)"

        hosts = roles[:alive_hosts].map(&:host)

        hosts.each do |hostname|
            cpu_cores(hostname).times do |core|
                ssh hostname, bundle_exec("rake mysql:stop RAILS_ENV=test TEST_ENV_NUMBER=#{core}")
                ssh hostname, bundle_exec("rake mysql:init_db RAILS_ENV=test TEST_ENV_NUMBER=#{core}")
                ssh hostname, bundle_exec("rake mysql:start RAILS_ENV=test TEST_ENV_NUMBER=#{core}")
                ssh hostname, bundle_exec("rake mysql:prepare TEST_ENV_NUMBER=#{core}")
            end
        end
    end
end
