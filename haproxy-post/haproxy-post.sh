#!/bin/bash
###########################################################
#
# Point haproxy to external swift proxies
# 2016, akaris@redhat.com
#
###########################################################

date +'%F %H:%M:%S' > /tmp/swift-haproxy-runtime.txt
echo "$ACTION" >> /tmp/swift-haproxy-runtime.txt
echo "$DEPLOY_UUID" >> /tmp/swift-haproxy-runtime.txt

# only execute on controllers
# assumption: if rabbitmq is running, then this is a controller node
# also check hostnames
if `ps aux | grep -q "[r]abbitmq-server"` || 
   `hostname | grep -iq "control"` ||
   `hostname | grep -iq "ctrl"`;then
  echo "This is a controller" >> /tmp/swift-haproxy-runtime.txt
else
  echo "This is not a controller, aborting script" >> /tmp/swift-haproxy-runtime.txt
  exit 0
fi

sed -i 's/listen swift_proxy_server/listen swift_proxy_server\n  mode http\n  option forwardfor header X-Client/' /etc/haproxy/haproxy.cfg 

# stop openstack-swift services and disable them on startup
# we don't want this to throw an error and make our deployment fail, so pipe stderr to /dev/null
systemctl list-units | grep openstack-swift | awk '{print $1}' | xargs -I {} systemctl stop {} 1>/dev/null 2>&1
systemctl list-units | grep openstack-swift | awk '{print $1}' | xargs -I {} systemctl disable {} 1>/dev/null 2>&1

# restart haproxy-clone resource and resource cleanup
# we don't want this to throw an error and make our deployment fail, so pipe stderr to /dev/null
# start it in background, give it max. 5 minutes to complete, and kill
# this is a workaround, because the pcs resource restart hung during a test
pcs resource restart haproxy-clone 1>/dev/null 2>&1 &
PID_OF_PCS_RESTART=$!
if `echo "$PID_OF_PCS_RESTART" | egrep -q '[0-9]+'`;then
  c=0
  while [ $c -lt 300 ];do
    sleep 1;
    if ! `ps aux | awk '{print $2}' | grep -q "$PID_OF_PCS_RESTART"`;then
      break
    fi
    c=$[ $c + 1 ]
  done
  kill -9 $PID_OF_PCS_RESTART 1>/dev/null 2>&1 
fi

pcs resource cleanup 1>/dev/null 2>&1

exit 0
