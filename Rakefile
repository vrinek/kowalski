CONFIG = YAML.load_file("kowalski.yml")

task :push do
  sh "git push -f kowalski master"
  sh "ssh #{CONFIG["master"]["username"]}@#{CONFIG["master"]["hostname"]} \"cd #{CONFIG["master"]["sinatra_path"]} && git checkout master -- .\""
end

task :up do
  sh ".bin/unicorn --port 4567 --config-file unicorn_conf.rb --daemonize"
end

task :down do
  sh "kill $( cat .pid )"
  sh "rm .pid"
end
