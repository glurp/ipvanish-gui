# encoding: utf-8
# License: LGPL V2.1

require 'socket'
require 'thread'
require 'timeout'



def ip_speed_test(dt,&block)
  load(__FILE__)
  Thread.new do
    # http://download.thinkbroadband.com/512MB.zip
    iso="512MB.zip"
    path=""
    host="download.thinkbroadband.com"
    uri="http://#{host}"
    url="#{uri}#{path}/#{iso}"
    #gui_invoke { alert(url) }
    header= <<EOF
GET #{path}/#{iso} HTTP/1.0
User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux i686; rv:30.0) Gecko/20100101 Firefox/30.0
Host: #{host}
Connection: close

EOF
    header.gsub!(/\n/,"\r\n")
    puts header
    gs=0
    ts=Time.now
	  timeout(240) {
		  s = TCPSocket.open(host, 80) 
      s.sync=true
      s.print header
      content=s.recv(1)
      ts=Time.now
		  ss=0
      start=Time.now.to_f
		  loop  do
        content=s.recv(1024)
        break unless content && content.size>0
			  ss+=content.size
			  gs+=content.size
        now=Time.now.to_f
        if (now-start)>dt
          speed=ss/(1024*(now-start))
          if block
           block.call(ss,now-start,speed) 
          else
            puts "size #{ss} during #{now-start} seconds >> speed= #{speed} KB/s"
          end
				  ss=0
				  start=now
			  end
		  end
		  s.close
	  } rescue puts "Error #{$!}"
    s.close rescue nil
    if block
      block.call((gs/(1024*1024.0)).round(2),0,gs/(1024*(Time.now.to_f-ts.to_f))) 
    end
  end 
end


# tail -f on openvpn log file
def tailmf(filename,rok,rnok) 
  $thtail.kill if $thtail
  $thtail=Thread.new(filename) do |fn|
     sleep(0.1) until File.exists?(fn)
     size=( File.size(fn) rescue 0)
     loop {
       File.open(fn) do |ff|
          ff.seek(size) if size>0 && size<=File.size(fn)
          while line=ff.gets
             size=ff.tell
             log(line.chomp.split(/\s+/,6)[-1]) 
             case line
               when rok
                 log "OK !!!!"
	               gui_invoke {
                   status_connection(true)
                 } 
               when rnok
                 log "AiiAiiAii !!!!"
               when /Connection reset, restarting/i
                 log "DECONNEXION !!!!"
	               gui_invoke {
                   status_connection(false)
                 } 
             end              
             sleep 0.07
          end
          #log "#{fn} closed"
       end
       sleep 0.2
     }
  end
end

def log(*s)  
  gui_invoke { log s.force_encoding("UTF-8") } 
end


if $0==__FILE__
  th=ip_speed_test(1) { |qt,delta,speed| puts "speed #{speed.round} KB/s" }
  sleep 30
  puts "kill thread..."
  th.kill
end

