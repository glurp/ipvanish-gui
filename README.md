IPVANISH-GUI for linux
======================


Gtk application for manage client connexion to VPN server.
Connection to IPVanish are supported.

based on Ruby, Gtk3, Ruiby (ruby dsl for gtk)

login/password are save in local file, uncryped.
Features are :
* load list server from ipvanish
* let user choose one country/town/server
* connect/disconnect
* check if connection is ready on vpn (http geoip.com)
* speed test (download a big file from public repo)
* memorise login/password, forget memorisation

Usage
=====
> cd ipvanish-gui; gksudo ruby ipvanish.rb &

Installation
============
Install openvpn, ruby, and some ruby extentions :

```
     <<< install openvpn and ruby 2.0 or + , from your distribution or rvm script>>>
    > sudo apt-get install openvpn
    > sudo gem install pty expect rubyzip Ruiby
    > git clone https://github.com/glurp/ipvanish-gui.git
    > cd ipvanish-gui
    > sudo ruby ipvanish.rb &
```

License
=======
LGPL V2.1



 
