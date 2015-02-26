Logstash installer for Rhel7 with Cloudforms evm.log filter
===========================================================
* Author: Laurent Domb
* Email: <laurent@redhat.com>
* Date: 2015-02-26
* Revision: 0.1


## Introduction
This script will setup a logstash instance on RHEL7 and will add a filter for cloudforms/ManageIQ evm.log or automation.log. 

## Setup
* Download https://raw.githubusercontent.com/ldomb/elkformiqonrhel7/master/installelkonel7formiq.sh
* Make it executable ( chmod +x installelkonel7formiq.sh)
* Add the all the info for:
POOL_ID=<poolid>
LG_SERVER_FQDN=<logstash_fqdh>
LG_SERVER_SHORT=<logstash_short>
HT_PASS=<htpassword>
LG_SERVER_IP=<lg_server_ip>

* Launch the script ./installelkonel7formiq.sh
