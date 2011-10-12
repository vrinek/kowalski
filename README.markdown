# Kowalski - distributed testing penguin on Rails

Kowalski is coded to be as hackable as possible, please look though the files and hack what you need in them for your project.

### Kowalski provides:

* some capistrano tasks to setup runners for distributed testing
* a sinatra app as a frontend to those tasks

### Kowalski needs:

* a user in each runner machine
* a git repo with the project
* rake tasks in the project to handle all services needed for testing (MySQL, MongoDB, Redis, ...)
* ruby and rubygems to be installed system-wide
* binary dependencies of gems to be met (should be if runner is a developer's machine)
* spork to have been setup properly in the project

### Current Kowalski limitation:

* limited configuration through kowalski.yml
* only one runner per machine (no multi-core yet)
* NEEDS the tmpfs in fstab (WIP to make it optional)
* has to be hacked to change versions of services and setup/preparation procedures
* only RSpec is supported

## Installation

    git clone git://github.com/vrinek/kowalski.git
    cd kowalski

    # get the needed gems
    bundle install

    # setup the config
    cp kowalski.yml.sample kowalski.yml
    {mate|vim|emacs} kowalski.yml

    # start hacking the capistrano tasks
    {mate|vim|emacs} Capfile capistrano/*

## Usage

Set up SSH access, ruby and everything else in capistrano/setup.rb

    cap setup

Prepare needed services (found in Capfile and capistrano/prepare.rb)

    cap up

Run the specs

    cap run_specs

Drop all services on runners (found in Capfile) and frees up the machines' resources

    cap down

Boot up the sinatra front

    rake up

Kill the sinatra front

    rake down

## Tips

* Spork does not need to be setup properly if you don't use it in day-to-day testing. Just install it and put all the contents from spec_helper.rb in the `Spork.preload` block. On every spec run, spork gets up (and loads the environment) and after the run is goes down so every run is fresh.
