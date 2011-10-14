# this should be run as the user that runs the specs
echo "Please ask an admin to add the following line at the end of your /etc/fstab:

none  $HOME/tmp  tmpfs  user,noauto,size=1000M,uid=$( id $( whoami ) -u ),gid=$( id $( whoami ) -g )  0  0
"
mkdir -p ~/tmp
