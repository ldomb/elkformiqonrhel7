#!/bin/sh
## This script meant to speed up the process
## around setting up a logstash server in preparation for miq logging 
#
# GPL 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>
WKD=`pwd`
POOL_ID=<poolid>
LG_SERVER_FQDN=<logstash_fqdh>
LG_SERVER_SHORT=<logstash_short>
HT_PASS=<htpassword>
LG_SERVER_IP=<lg_server_ip>

echo -e "\n ## Disableing ipv6\n"
cat >> /etc/sysctl.d/99-disableipv6.conf << EOF
net.ipv6.conf.all.disable_ipv6=1
EOF
sysctl -p /etc/sysctl.d/99-disableipv6.conf

echo -e "\n ## Adding entry to /etc/hosts\n"
cat >> /etc/hosts << EOF
$LG_SERVER_IP	$LG_SERVER_FQDN	$LG_SERVER_SHORT
EOF

echo -e "\n ## Subscribing to Redhat..\n"
subscription-manager register
subscription-manager attach --pool=$POOL_ID
subscription-manager repos --disable=*
subscription-manager repos --enable=rhel-7-server-rpms --enable=rhel-7-server-rh-common-rpms --enable=rhel-7-server-optional-beta-rpms

echo -e "\n ## Disable firewall\n"
systemctl stop firewalld
systemctl disable firewalld

echo -e "\n ## set selinux to permissive\n"
sed -i s/SELINUX=enforcing/SELINUX=permissve/g /etc/selinux/config
setenforce 0

echo -e "\n ## add the logstash repo\n"
rpm --import http://packages.elasticsearch.org/GPG-KEY-elasticsearch
cat > /etc/yum.repos.d/elasticsearch.repo << EOF
[elasticsearch-1.3]
name=Elasticsearch repository for 1.3.x packages
baseurl=http://packages.elasticsearch.org/elasticsearch/1.3/centos
gpgcheck=1
gpgkey=http://packages.elasticsearch.org/GPG-KEY-elasticsearch
enabled=1
EOF

echo -e "\n ## installing elasticsearch java and httpd\n"
yum install -y elasticsearch java-1.7.0-openjdk httpd

echo -e "\n ## disable dynamic scripts in elasticsearch\n"
cat >> /etc/elasticsearch/elasticsearch.yml << EOF
### Custom config parameters
script.disable_dynamic: true
EOF

echo -e "\n ## configuring elasticsearch to start at boot time\n"
systemctl daemon-reload
systemctl enable elasticsearch.service
systemctl start elasticsearch.service

echo -e "\n ## install kibana\n"
wget -P /var/www/html/ https://download.elasticsearch.org/kibana/kibana/kibana-3.1.0.tar.gz
tar -xzvf /var/www/html/kibana-3.1.0.tar.gz -C /var/www/html
mv /var/www/html/kibana-3.1.0 /var/www/html/kibana3
rm -f /var/www/html/kibana-3.1.0.tar.gz
rm -f /var/www/html/kibana-3.1.0
mkdir -p /var/www/html/kibana3/pub

echo -e "\n ## adding port 80 to kibana\n"
sed -i "s@elasticsearch: \"http://\"+window.location.hostname+\":9200\"@elasticsearch: \"http://\"+window.location.hostname+\":80\"@g" /var/www/html/kibana3/config.js 

echo -e "\n ## add httpd config\n"
cat >> /etc/httpd/conf.d/kibana3.conf << EOF
<VirtualHost $LG_SERVER_FQDN:80>
  ServerName $LG_SERVER_FQDN
 
  DocumentRoot /var/www/html/kibana3
  <Directory /var/www/html/kibana3>
    Allow from all
    Options -Multiviews
  </Directory>
 
  LogLevel debug
  ErrorLog /var/log/httpd/error_log
  CustomLog /var/log/httpd/access_log combined
 
  # Proxy for _aliases and .*/_search
  <LocationMatch "^/(_nodes|_aliases|.*/_aliases|_search|.*/_search|_mapping|.*/_mapping)$">
    ProxyPassMatch http://127.0.0.1:9200/$1
    ProxyPassReverse http://127.0.0.1:9200/$1
  </LocationMatch>
 
  # Proxy for kibana-int/{dashboard,temp} stuff (if you don't want auth on /, then you will want these to be protected)
  <LocationMatch "^/(kibana-int/dashboard/|kibana-int/temp)(.*)$">
    ProxyPassMatch http://127.0.0.1:9200/$1$2
    ProxyPassReverse http://127.0.0.1:9200/$1$2
  </LocationMatch>
 
  <Location />
    AuthType Basic
    AuthBasicProvider file
    AuthName "Restricted"
    AuthUserFile /etc/httpd/conf.d/kibana-htpasswd
    Require valid-user
  </Location>
</VirtualHost>
EOF

echo -e "\n ## Setting htpasswd\n"
htpasswd -c /etc/httpd/conf.d/kibana-htpasswd admin
rm -rf /etc/httpd/conf.d/welcome.conf

echo -e "\n ## starting and enableing apache\n"
systemctl enable httpd
systemctl start httpd

echo -e "\n ## Adding logstash repos\n"
cat > /etc/yum.repos.d/logstash.repo << EOF
[logstash-1.4]
name=logstash repository for 1.4.x packages
baseurl=http://packages.elasticsearch.org/logstash/1.4/centos
gpgcheck=1
gpgkey=http://packages.elasticsearch.org/GPG-KEY-elasticsearch
enabled=1
EOF

echo -e "\n ## Installing logstash\n"
yum install -y logstash

echo -e "\n ## installing golang and build lc-tlscert.go to create ssl cert\n"
yum install golang -y
wget https://raw.githubusercontent.com/driskell/log-courier/develop/src/lc-tlscert/lc-tlscert.go
go build lc-tlscert.go
$WKD/lc-tlscert

echo -e "\n ## Move ssl certs into logstashes ssl dir and copy\n"
mkdir -p /etc/logstash/ssl/
mv /root/selfsigned.crt /etc/logstash/ssl/logstash-forwarder.crt; chmod 666 /etc/logstash/ssl/logstash-forwarder.crt
mv /root/selfsigned.key /etc/logstash/ssl/logstash-forwarder.key; chmod 666 /etc/logstash/ssl/logstash-forwarder.key
cp /etc/logstash/logstash-forwarder.crt /var/www/html/kibana3/pub/

echo -e "\n ## Create lumberjack input config\n"
cat > /etc/logstash/conf.d/01-lumberjack-input.conf << EOF
input {
  lumberjack {
    port => 5000
    type => "logs"
    ssl_certificate => "/etc/logstash/ssl/logstash-forwarder.crt"
    ssl_key => "/etc/logstash/ssl/logstash-forwarder.key"
  }
}
EOF

echo -e "\n ## Create miq-filter\n"
cat > /etc/logstash/conf.d/11-miq.conf << EOF
filter {
  if [type] == "miqautomation" {
    grok {
      patterns_dir => "/opt/logstash/pattern" 
      match => { "message" => "%{DATE}T%{TIME}%{SPACE}#%{WORD}:%{WORD}%{NOTSPACE}%{SPACE}%{RUBY_LOGLEVEL}%{SPACE}%{NOTSPACE}%{SPACE}%{NOTSPACE}%{SPACE}%{NOTSPACE}%{WORD:task_id}%{NOTSPACE}%{GREEDYDATA:miq_msg}" }
    }
  }
}
EOF


echo -e "\n ## Create logstash output config\n"
cat > /etc/logstash/conf.d/30-lumberjack-output.conf << EOF
output {
  elasticsearch { host => localhost }
  stdout { codec => rubydebug }
}
EOF

echo -e "\n ## starting logstash\n"
chkconfig logstash on 
service logstash restart


echo -e "\n ## getting client configs\n"
cd /var/www/html/kibana3/pub
wget http://download.elasticsearch.org/logstash-forwarder/packages/logstash-forwarder-0.3.1-1.x86_64.rpm
wget http://logstashbook.com/code/4/logstash_forwarder_redhat_init
wget http://logstashbook.com/code/4/logstash_forwarder_redhat_sysconfig
cat > /var/www/html/kibana3/pub/logstash-forwarder-installer.sh << EOF2
#!/bin/bash
wget -P /tmp/ --user=admin --password=$HT_PASS http://$LG_SERVER_FQDN/pub/logstash-forwarder-0.3.1-1.x86_64.rpm
yum -y localinstall /tmp/logstash-forwarder-0.3.1-1.x86_64.rpm
rm -f /tmp/logstash-forwarder-0.3.1-1.x86_64.rpm
wget -O /etc/init.d/logstash-forwarder --user=$HT_PASS --password=yourpassword http://$LG_SERVER_FQDN/pub/logstash_forwarder_redhat_init
chmod +x /etc/init.d/logstash-forwarder
wget -O /etc/sysconfig/logstash-forwarder --user=admin --password=$HT_PASS dhttp://$LG_SERVER_FQDN/pub/logstash_forwarder_redhat_sysconfig
wget -P /etc/pki/tls/certs/ --user=admin --password=$HT_PASS http://$LG_SERVER_FQDN/pub/logstash-forwarder.crt
mkdir -p /etc/logstash-forwarder
cat > /etc/logstash-forwarder/logstash-forwarder.conf << EOF
{
  "network": {
    "servers": [ "$LG_SERVER_FQDN:5000" ],
    "timeout": 15,
    "ssl ca": "/etc/pki/tls/certs/logstash-forwarder.crt"
  },
  "files": [
    {
      "paths": [
        "/var/www/miq/vmdb/log/evm.log"
      ],
      "fields": { "type": "miqautomation" }
    }
   ]
}
EOF

chkconfig --add logstash-forwarder
service logstash-forwarder start
EOF2

echo -e "\n ## YOUR DONE. WE WILL REBOOT NOW. LOGIN TO THE CF APPLIANCE and launch the install script\n"
init 6
