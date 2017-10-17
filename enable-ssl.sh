#!/bin/bash 
function set_ssh {
    echo Setting SSH Config
    #remove ssh host key checks
    cat <<EOF > ~/.ssh/config
    Host *
    PasswordAuthentication no
    StrictHostKeyChecking no
    ConnectTimeout 20
EOF
}
function get_nodes {
    #yum install -y epel-release
    #yum install -y jq
    curl -H "X-Requested-By: ambari" -X GET -u admin:admin http://192.168.178.36:8080/api/v1/clusters/sandbox/hosts > hosts.json
    
    readarray HOSTS <<< "$(jq -r '.items[] | .Hosts | .host_name' hosts.json)";
    
    for x in "${HOSTS[@]}"; 
    do 
	ssh $x /bin/bash <<'ENDSSH' 
	echo $(hostname -f)
    	ls
	ENDSSH
    done   
}

function quit {
  exit
}
function hello {
 echo ${DOMAIN}!
}
set_ssh
get_nodes
DOMAIN=$(hostname -d)
#hello
quit
echo foo 
