RUBY_VERSION='1.9.3'
RUBY_PATCHLEVEL='0'

cd $HOME
touch $HOME/.bash_profile
source $HOME/.bash_profile

if [ "$( which rbenv )" = "" ]; then
    echo "Installing rbenv"
    git clone git://github.com/sstephenson/rbenv.git .rbenv
    echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bash_profile
    echo 'eval "$(rbenv init -)"' >> ~/.bash_profile
fi

if [ "$( which ruby-build )" = "" ]; then
    echo "Installing ruby-build"
    mkdir -p $HOME/src
    git clone git://github.com/sstephenson/ruby-build.git $HOME/src/ruby-build
    echo 'export PATH="$HOME/.ruby-build/bin:$PATH"' >> ~/.bash_profile
    cd $HOME/src/ruby-build
    PREFIX=$HOME/.ruby-build ./install.sh
    cd ~
fi

source $HOME/.bash_profile

if [ "$( which ruby )" = "$HOME/.rbenv/shims/ruby" ]; then
    if [ "$( ruby --version | grep $RUBY_VERSION | grep 'patchlevel $RUBY_PATCHLEVEL' )" != "" ]; then
        NEED_TO_INSTALL_RUBY=false
    else
        NEED_TO_INSTALL_RUBY=true
    fi
else
    NEED_TO_INSTALL_RUBY=true
fi

if [ $NEED_TO_INSTALL_RUBY = true ]; then
    echo "Installing ruby $RUBY_VERSION-p$RUBY_PATCHLEVEL"
    rbenv install $RUBY_VERSION-p$RUBY_PATCHLEVEL
    rbenv global $RUBY_VERSION-p$RUBY_PATCHLEVEL
else
    echo "Ruby $RUBY_VERSION-p$RUBY_PATCHLEVEL is installed"
fi
