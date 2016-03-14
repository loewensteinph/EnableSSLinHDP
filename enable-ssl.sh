#!/usr/bin/env bash

OOZIE_SERVER="sandbox.hortonworks.com"
RANGER_ADMIN_SERVER="sandbox.hortonworks.com"
NAMENODE_SERVER="sandbox.hortonworks.com"
HBASE_REGION_SERVER="sandbox.hortonworks.com"
export AMBARI_SERVER="sandbox.hortonworks.com"
HBASE_MASTER_SERVER="sandbox.hortonworks.com"

AMBARI_PASS=4o12t0n
CLUSTER_NAME=Sandbox
#
# PREP
#
mkdir -p /tmp/security
chmod -R 755 /tmp/security
cd /tmp/security
TRUST_STORE=/etc/pki/java/cacerts

#
# create all SSL certificates, and keys
# 1. CA SSL certificate
# 2. Server SSL certificate
# 3. Ranger HBase plugin certificate
# 4. Ranger HDFS plugin certificate
#
function generateSSLCerts() {
    # 1. CA SSL certificate
    if [ ! -e "ca.crt" ]; then
        openssl genrsa -out ca.key 2048
        openssl req -new -x509 -days 1826 -key ca.key -out ca.crt -subj "/C=US/ST=New York/L=New York City/O=Hortonworks/OU=Consulting/CN=HortonworksCA"
    fi

    # 2. Server SSL certificates
    for host in $OOZIE_SERVER $RANGER_ADMIN_SERVER $NAMENODE_SERVER $HBASE_REGION_SERVER $AMBARI_SERVER $HBASE_MASTER_SERVER; do
     if [  -e "${host}.crt" ]; then break; fi
        openssl req -new -newkey rsa:2048 -nodes -keyout ${host}.key -out ${host}.csr  -subj "/C=US/ST=New York/L=New York City/O=Hortonworks/OU=Consulting/CN=$host"
        openssl x509 -req -days 365 -in ${host}.csr -CA ca.crt -CAkey ca.key -out ${host}.crt -set_serial 01
    done

    # 3. Ranger HDFS plugin certificate
    if [ ! -e "rangerHdfsAgent.crt" ]; then
        openssl req -new -newkey rsa:2048 -nodes -keyout rangerHdfsAgent.key -out rangerHdfsAgent.csr  -subj "/C=US/ST=New York/L=New York City/O=Hortonworks/OU=Consulting/CN=HdfsPlugin"
        openssl x509 -req -days 365 -in rangerHdfsAgent.csr -CA ca.crt -CAkey ca.key -out rangerHdfsAgent.crt -set_serial 01
    fi

    # 4. Ranger HBase plugin certificate
    if [ ! -e "rangerHbaseAgent.crt" ]; then
        openssl req -new -newkey rsa:2048 -nodes -keyout rangerHbaseAgent.key -out rangerHbaseAgent.csr  -subj "/C=US/ST=New York/L=New York City/O=Hortonworks/OU=Consulting/CN=HbasePlugin"
        openssl x509 -req -days 365 -in rangerHbaseAgent.csr -CA ca.crt -CAkey ca.key -out rangerHbaseAgent.crt -set_serial 01
    fi
}
#
# Enable Oozie UI SSL encryption, execute on the Oozie server after copying necessary files
#
function oozieSSLEnable() {
    openssl pkcs12 -export -in ${OOZIE_SERVER}.crt -inkey ${OOZIE_SERVER}.key -out oozie-server.p12 -name tomcat -CAfile NotApplicable -caname root -passout pass:password
    su - oozie -c "keytool --importkeystore -noprompt -deststorepass password -destkeypass password -destkeystore ~/.keystore -srckeystore /tmp/security/oozie-server.p12 -srcstoretype PKCS12 -srcstorepass password -alias tomcat"
    keytool -import -noprompt -alias HortonworksCA -file ca.crt -storepass changeit -keystore $TRUST_STORE
    keytool -import -noprompt -alias tomcat -file ${OOZIE_SERVER}.crt -storepass changeit -keystore $TRUST_STORE

    /var/lib/ambari-server/resources/scripts/configs.sh -u admin -p $AMBARI_PASS set $AMBARI_SERVER $CLUSTER_NAME oozie-site oozie.base.url https://${OOZIE_SERVER}s.com:11443/oozie &> /dev/null

    echo "
    Now edit oozie-env in Ambari and add to the end of oozie-env template:
    export OOZIE_HTTP_PORT=11000
    export OOZIE_HTTPS_PORT=11443

    Then restart Oozie
    "
    #

    #validate using
    # openssl s_client -connect ${OOZIE_SERVER}:11443 -showcerts
    #
}
#
# Enable Ambari SSL encryption
#
function ambariSSLEnable() {
    rpm -q expect || yum install -y expect
    cat <<EOF > ambari-ssl-expect.exp
#!/usr/bin/expect
spawn "/usr/sbin/ambari-server" "setup-security"
expect "Enter choice"
send "1\r"
expect "Do you want to configure HTTPS"
send "y\r"
expect "SSL port"
send "\r"
expect "Enter path to Certificate"
send "/tmp/security/\$env(AMBARI_SERVER).crt\r"
expect "Enter path to Private Key"
send "/tmp/security/\$env(AMBARI_SERVER).key\r"
expect "Please enter password for Private Key"
send "\r"
send "\r"
interact
EOF

    cat <<EOF > ambari-truststore-expect.exp
#!/usr/bin/expect
spawn "/usr/sbin/ambari-server" "setup-security"
expect "Enter choice"
send "4\r"
expect "Do you want to configure a truststore"
send "y\r"
expect "TrustStore type"
send "jks\r"
expect "Path to TrustStore file"
send "/etc/pki/java/cacerts\r"
expect "Password for TrustStore"
send "changeit\r"
expect "Re-enter password"
send "changeit\r"
interact
EOF

    if ! grep -q 'api.ssl=true' /etc/ambari-server/conf/ambari.properties; then
        /usr/bin/expect ambari-ssl-expect.exp
	/usr/bin/expect ambari-truststore-expect.exp

    	service ambari-server restart
    fi

    #validate wget -O-  --no-check-certificate "https://sandbox.hortonworks.com:8443/#/main/dashboard/metrics"
}
#
# Enable Hadoop UIs SSL encryption.  Execute on each NameNode, ResourceManager, YARN History Server, and JournalNode after copying necessary files.  The keystore (.jks) should be the same on all hosts. Pre-requisite is that you enable Ambari SSL encryption
#
function hadoopSSLEnable() {
    chmod 440 /etc/hadoop/conf/hadoop-private-keystore.jks
    chown yarn:hadoop /etc/hadoop/conf/hadoop-private-keystore.jks

    keytool -import -noprompt -alias HortonworksCA -file ca.crt -storepass changeit -keystore $TRUST_STORE
    keytool -import -noprompt -alias HortonworksCA -file ca.crt -storepass password -keypass password -keystore /etc/hadoop/conf/hadoop-private-keystore.jks
    openssl pkcs12 -export -in ${NAMENODE_SERVER}.crt -inkey ${NAMENODE_SERVER}.key -out namenode-server.p12 -name ${NAMENODE_SERVER} -CAfile NotApplicable -caname root -passout pass:password
    keytool --importkeystore -noprompt -deststorepass password -destkeypass password -destkeystore /etc/hadoop/conf/hadoop-private-keystore.jks -srckeystore namenode-server.p12 -srcstoretype PKCS12 -srcstorepass password -alias ${NAMENODE_SERVER}

    cat <<EOF | while read p; do p=${p/,}; p=${p//\"}; if [ -z "$p" ]; then continue; fi; /var/lib/ambari-server/resources/scripts/configs.sh -u admin -p $AMBARI_PASS -port 8443 -s set $AMBARI_SERVER $CLUSTER_NAME $p &> /dev/null || echo "Failed to change $p in Ambari"; done
        hdfs-site "dfs.https.enable"   "true",
        hdfs-site "dfs.http.policy"   "HTTPS_ONLY",
        hdfs-site "dfs.datanode.https.address"   "0.0.0.0:50475",
        hdfs-site "dfs.namenode.https-address"   "0.0.0.0:50470",

        core-site "hadoop.ssl.require.client.cert"   "false",
        core-site "hadoop.ssl.hostname.verifier"   "DEFAULT",
        core-site "hadoop.ssl.keystores.factory.class"   "org.apache.hadoop.security.ssl.FileBasedKeyStoresFactory",
        core-site "hadoop.ssl.server.conf"   "ssl-server.xml",
        core-site "hadoop.ssl.client.conf"   "ssl-client.xml",

        mapred-site "mapreduce.jobhistory.http.policy"   "HTTPS_ONLY",
        mapred-site "mapreduce.jobhistory.webapp.https.address"   "${NAMENODE_SERVER}:19443",

        yarn-site "yarn.http.policy"   "HTTPS_ONLY"
        yarn-site "yarn.log.server.url"   "https://${NAMENODE_SERVER}:19443/jobhistory/logs",
        yarn-site "yarn.resourcemanager.webapp.https.address"   "${NAMENODE_SERVER}:8090",
        yarn-site "yarn.nodemanager.webapp.https.address"   "0.0.0.0:45443",

        ssl-server "ssl.server.keystore.password"   "password",
        ssl-server "ssl.server.keystore.keypassword"   "password",
        ssl-server "ssl.server.keystore.location"   "/etc/hadoop/conf/hadoop-private-keystore.jks",
        ssl-server "ssl.server.truststore.location"   "${TRUST_STORE}",
        ssl-server "ssl.server.truststore.password"   "changeit",

        ssl-client "ssl.client.keystore.location"   "${TRUST_STORE}",
        ssl-client "ssl.client.keystore.password"   "changeit",
        ssl-client "ssl.client.truststore.password"   "changeit",
        ssl-client "ssl.client.truststore.location"   "${TRUST_STORE}"

EOF

# Restart HDFS, YARN, and Map Reduce components in Ambari

}

#
# Enable HBase UI SSL encryption.  Execute on each HBase Master after copying necessary files.  The keystore (.jks) should be the same on all HBase Masters.  Pre-requisite is that you enable Hadoop, and Ambari SSL encryption
#
function hbaseSSLEnable() {
    keytool -import -noprompt -alias HortonworksCA -file ca.crt -storepass changeit -keystore $TRUST_STORE
    keytool -import -noprompt -alias HortonworksCA -file ca.crt -storepass password -keypass password -keystore /etc/hadoop/conf/hadoop-private-keystore.jks
    openssl pkcs12 -export -in ${HBASE_MASTER_SERVER}.crt -inkey ${HBASE_MASTER_SERVER}.key -out hbase-master-server.p12 -name ${HBASE_MASTER_SERVER} -CAfile NotApplicable -caname root -passout pass:password
    keytool --importkeystore -noprompt -deststorepass password -destkeypass password -destkeystore /etc/hadoop/conf/hadoop-private-keystore.jks -srckeystore hbase-master-server.p12 -srcstoretype PKCS12 -srcstorepass password -alias ${HBASE_MASTER_SERVER}

    /var/lib/ambari-server/resources/scripts/configs.sh -u admin -p $AMBARI_PASS -port 8443 -s set $AMBARI_SERVER $CLUSTER_NAME hbase-site "hbase.ssl.enabled" "true" &> /dev/null || echo "Failed to change hbase.ssl.enabled in Ambari"
}

#
# Enable Ranger Admin UI SSL Encryotion
#
function rangerAdminSSLEnable() {
    openssl pkcs12  -export -in  ${RANGER_ADMIN_SERVER}.crt -inkey ${RANGER_ADMIN_SERVER}.key -out ranger-admin.p12 -name rangeradmin -CAfile NotApplicable -caname root -passout pass:password
    keytool --importkeystore -noprompt -deststorepass password -destkeypass password -destkeystore /etc/ranger/admin/conf/ranger-admin-keystore.jks -srckeystore ranger-admin.p12 -srcstoretype PKCS12 -srcstorepass password -alias rangeradmin

    cat <<EOF | while read p; do p=${p/,}; p=${p//\"}; if [ -z "$p" ]; then continue; fi; /var/lib/ambari-server/resources/scripts/configs.sh -u admin -p $AMBARI_PASS -port 8443 -s set $AMBARI_SERVER $CLUSTER_NAME $p &>/dev/null  || echo "Failed to change $p in Ambari"; done
        ranger-admin-site "ranger.service.http.enabled"   "false",
        ranger-admin-site "ranger.service.https.attrib.clientAuth"   "false",
        ranger-admin-site "ranger.service.https.attrib.keystore.pass"   "password",
        ranger-admin-site "ranger.service.https.attrib.ssl.enabled"   "true",

        ranger-ugsync-site "ranger.usersync.truststore.file" "${TRUST_STORE}",
        ranger-ugsync-site "ranger.usersync.truststore.password" "changeit",

        admin-properties "policymgr_external_url"  "https://${RANGER_ADMIN_SERVER}:6182"
EOF

}
#
# Ranger HDFS Plugin
#
function rangerHDFSSSLEnable() {
    openssl pkcs12 -export -in rangerHdfsAgent.crt -inkey rangerHdfsAgent.key -out rangerHdfsAgent.p12 -name rangerHdfsAgent -CAfile NotApplicable -caname root -passout pass:password

    keytool -importkeystore -noprompt -deststorepass password -destkeypass password -destkeystore /etc/hadoop/conf/ranger-plugin-keystore.jks  -srckeystore rangerHdfsAgent.p12 -srcstoretype PKCS12 -srcstorepass password -alias rangerHdfsAgent

    keytool -import -noprompt -alias rangeradmintrust -file ${RANGER_ADMIN_SERVER}.crt -storepass password -keystore /etc/hadoop/conf/ranger-plugin-keystore.jks
    chown hdfs:hadoop /etc/hadoop/conf/ranger-plugin-keystore.jks
    chmod 400 /etc/hadoop/conf/ranger-plugin-keystore.jks

    keytool -import -noprompt -alias rangerHdfsAgent -file rangerHdfsAgent.crt -storepass changeit -keystore $TRUST_STORE

    cat <<EOF | while read p; do p=${p/,}; p=${p//\"}; if [ -z "$p" ]; then continue; fi; /var/lib/ambari-server/resources/scripts/configs.sh -u admin -p $AMBARI_PASS -port 8443 -s set $AMBARI_SERVER $CLUSTER_NAME $p &> /dev/null || echo "Failed to change $p in Ambari"; done

        ranger-hdfs-policymgr-ssl "xasecure.policymgr.clientssl.keystore"   /etc/hadoop/conf/ranger-plugin-keystore.jks,
        ranger-hdfs-policymgr-ssl "xasecure.policymgr.clientssl.keystore.password"   "password",
        ranger-hdfs-policymgr-ssl "xasecure.policymgr.clientssl.truststore"  "${TRUST_STORE}",
        ranger-hdfs-policymgr-ssl "xasecure.policymgr.clientssl.truststore.password"   "changeit"
EOF

}
#
# Ranger HBase Plugin
#
function rangerHBaseSSLEnable() {
    openssl pkcs12 -export -in rangerHbaseAgent.crt -inkey rangerHbaseAgent.key -out rangerHbaseAgent.p12 -name rangerHbaseAgent -CAfile NotApplicable -caname root -passout pass:password

    RANGER_PLUGIN_PRIVATE_STORE=
    keytool -importkeystore -noprompt -deststorepass password -destkeypass password -destkeystore /etc/hadoop/conf/ranger-plugin-keystore.jks  -srckeystore rangerHbaseAgent.p12 -srcstoretype PKCS12 -srcstorepass password -alias rangerHbaseAgent

    keytool -import -noprompt -alias rangeradmintrust -file ${RANGER_ADMIN_SERVER}.crt -storepass password -keystore /etc/hadoop/conf/ranger-plugin-keystore.jks
    chown hbase:hadoop /etc/hadoop/conf/ranger-plugin-keystore.jks
    chmod 440 /etc/hadoop/conf/ranger-plugin-keystore.jks

    keytool -import -noprompt -alias rangerHbaseAgent -file rangerHbaseAgent.crt -storepass changeit -keystore $TRUST_STORE

    cat <<EOF | while read p; do p=${p/,}; p=${p//\"}; if [ -z "$p" ]; then continue; fi; /var/lib/ambari-server/resources/scripts/configs.sh -u admin -p $AMBARI_PASS -port 8443 -s set $AMBARI_SERVER $CLUSTER_NAME $p &> /dev/null || echo "Failed to change $p in Ambari"; done

        ranger-hbase-policymgr-ssl "xasecure.policymgr.clientssl.keystore"  /etc/hadoop/conf/ranger-plugin-keystore.jks,
        ranger-hbase-policymgr-ssl "xasecure.policymgr.clientssl.keystore.password"  "password"
        ranger-hbase-policymgr-ssl "xasecure.policymgr.clientssl.truststore" "${TRUST_STORE}",
        ranger-hbase-policymgr-ssl "xasecure.policymgr.clientssl.truststore.password"  "changeit"
EOF
}

function usage() {
    echo "Usage: $0 [--all] [--hbaseSSL] [--oozieSSL] [--hadoopSSL] [ --rangerSSL] [--ambariSSL]"
    exit 1
}

if [ "$#" -lt 1 ]; then
    usage
fi

while [ "$#" -ge 1 ]; do
    key="$1"

    case $key in
        --all)
            generateSSLCerts
            ambariSSLEnable
            oozieSSLEnable
            hadoopSSLEnable
            hbaseSSLEnable
            rangerAdminSSLEnable
            rangerHDFSSSLEnable
            rangerHBaseSSLEnable
        ;;
        --hbaseSSL)
            generateSSLCerts
            ambariSSLEnable
            hadoopSSLEnable
            hbaseSSLEnable
        ;;
        --oozieSSL)
            generateSSLCerts
            ambariSSLEnable
            oozieSSLEnable
        ;;
        --hadoopSSL)
            generateSSLCerts
            ambariSSLEnable
            hadoopSSLEnable
        ;;
        --rangerSSL)
            generateSSLCerts
            ambariSSLEnable
            rangerAdminSSLEnable
            rangerHDFSSSLEnable
            rangerHBaseSSLEnable
        ;;
        --ambariSSL)
            generateSSLCerts
            ambariSSLEnable
        ;;
        *)
            usage
        ;;
    esac
    shift # past argument or value
done