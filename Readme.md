<h1>Summary</h1>
<p>
	Enabling SSL encryption for the Web UIs that make up Hadoop is a tedious process that requires planning, learning to use security tools, and lots of mouse clicks through Ambari's UI.  This article aims to simplify the process by presenting a semi-automated, start-to-finish example that enables SSL for the below Web UIs in the Hortonworks Sandbox:
</p>
<ol>
	<li>Ambari</li>
	<li>HBase</li>
	<li>Oozie</li>
	<li>Ranger</li>
	<li>HDFS</li>
</ol>
<h2>Planning</h2>
<p>
	There is no substitute for reading the
	<a href="http://docs.hortonworks.com">documentation</a>.  If you plan on enabling SSL in a production cluster, then make sure you are familiar with SSL concepts and the communication paths between each HDP component.  In addition, plan on cluster downtime.  Here are some concepts that you should know well:
</p>
<ol>
	<li><strong>Certificate Authority (CA)</strong></li>
			A Certificate Authority is a company that others trust that signs certificates for a fee.  On a Mac you can view a list of CAs that your computer trusts by opening up the "Keychain Access" application and clicking on "System Roots".  If you don't want to pay one of these companies to sign your certificates, then you can generate your own CA, just beware the Google Chrome and other browsers will present you with a privacy warning.
	<li><strong>Server SSL certificate</strong></li>
			These are files that prove the identity of a something, in our case: HDP services.  Usually there is one certificate per hostname, and it is signed by a CA.  There are two pieces of a certificate: the private and public keys.  A private key is needed to encrypt a message and a public certificate is needed to decrypt the same message.
	<li><strong>Java private keystore</strong></li>
			When Java HDP services need to encrypt messages, they need a place to look for the private key part of a server's SSL certificate.  This keystore holds those private keys.  It should be kept secure so that attackers cannot impersonate the service.  For this reason, each HDP component in this article has its own private keystore.
	<li><strong>Java trust keystore</strong></li>
			Just like my Mac has a list of CAs that it trusts, a Java process on a Linux machine needs the same.  This keystore will usually hold the Public CA's certificate and any intermediary CA certificates.  If a certificate was signed with a CA that you created yourself then also add the public part of a server's SSL certificate into this keystore.
	<li><strong>Ranger plugins</strong></li>
			Ranger plugins communicate with Ranger Admin server over SSL.  What is important to understand is where each plugin executes and thus where server SSL certificates are needed.  For HDFS, the execution is on the NameNodes, for HBase, it is on the RegionServers, for YARN, it is on the ResourceManagers.  When you create server SSL certificates use the hostnames where the plugins execute.
</ol>
<h2>Enable SSL on HDP Sandbox</h2>
<p>
This part is rather easy.  Install the HDP 2.4 Sandbox and follow the below steps.  If you use an older version of the Sandbox note that you'll need to change the Ambari password used in the script.
</p>
<ol>
	<li>Download my script
	<pre>
wget "https://raw.githubusercontent.com/vzlatkin/EnableSSLinHDP/master/enable-ssl.sh"
	</pre>
	</li>
	<li>Stop all services via Ambari (manually stop HDFS or Turn Off Maintenance Mode)</li>
	<li>Execute:
	<pre>
/bin/bash enable-ssl.sh --all
	</pre>
	</li>
	<li>Start all services via Ambari, which is now running on port 8443</li>
	<li>Goto Ranger Admin UI and edit HDFS and HBase services to set the <em>Common Name for Certificate</em> to sandbox.hortonworks.com</li>
</ol>
<h2>Enable SSL in production</h2>
<p>
There are two big reasons why enabling SSL in production can be more difficult than in a sandbox:
</p>
<ol>
	<li>If Hadoop components run in Highly Available mode. The solution for most instances is to create a single server SSL certificate and copy it to all HA servers.  However, for Oozie you'll need a special server SSL certificate with <em>CN=*.domainname.com</em></li>
	<li>If using Public CAs to sign server SSL certificates.  Besides adding time to the process that is needed for the CA to sign your certificates you may also need additional steps to add intermediate CA certificates to the various Java trust stores and finding a CA that can sign non-FQDN server SSL certificates for Oozie HA</li>
</ol>
<p>
	If you are using Ranger to secure anything besides HBase and HDFS then you will need to make changes to the
	<a href="https://github.com/vzlatkin/EnableSSLinHDP/blob/master/enable-ssl.sh">script</a> to enable extra plugins.
The steps are similar to enabling SSL in Sanbox:
</p>
<ol>
	<li>Download my script
	<pre>
    wget "https://raw.githubusercontent.com/vzlatkin/EnableSSLinHDP/master/enable-ssl.sh"
	</pre>
	</li>
	<li>Make changes to these variables inside of the script to reflect your cluster layout.  The script uses these variables to generate certificates and copy them to all machines where they are needed.  Below is an example for my three node cluster.
	<pre>
server1="example1.hortonworks.com"
server2="example2.hortonworks.com"
server3="example3.hortonworks.com"
OOZIE_SERVER_ONE=$server2
NAMENODE_SERVER_ONE=$server1
RESOURCE_MANAGER_SERVER_ONE=$server3
HISTORY_SERVER=$server1
HBASE_MASTER_SERVER_ONE=$server2
RANGER_ADMIN_SERVER=$server1
ALL_NAMENODE_SERVERS="${NAMENODE_SERVER_ONE} $server2"
ALL_OOZIE_SERVERS="${OOZIE_SERVER_ONE} $server3"
ALL_HBASE_MASTER_SERVERS="${HBASE_MASTER_SERVER_ONE} $server3"
ALL_HBASE_REGION_SERVERS="$server1 $server2 $server3"
ALL_REAL_SERVERS="$server1 $server2 $server3"
ALL_HADOOP_SERVERS="$server1 $server2 $server3"
export AMBARI_SERVER=$server1
AMBARI_PASS=xxxx
CLUSTER_NAME=cluster1
	</pre>
	</li>
	<li>If you are going to pay a Public CA to sign your server SSL certificates then copy them to <em>/tmp/security</em> and name them as such:
	<pre>
ca.crt
example1.hortonworks.com.crt
example1.hortonworks.com.key
example2.hortonworks.com.crt
example2.hortonworks.com.key
example3.hortonworks.com.crt
example3.hortonworks.com.key
hortonworks.com.crt
hortonworks.com.key
	</pre>
	The last certificate is needed for Oozie if you have Oozie HA enabled.  The CN of that certificate should be
	<em>CN=*.domainname.com</em> as described <a href="https://oozie.apache.org/docs/4.1.0/AG_Install.html#To_use_a_Certificate_from_a_Certificate_Authority">here</a>If you are NOT going to use a Public CA to sign your certificates, then change these lines in the script to be relevant to your organization:
	<pre>
/C=US/ST=New York/L=New York City/O=Hortonworks/OU=Consulting/CN=HortonworksCA
	</pre>
	</li>
	<li>Stop all services via Ambari</li>
	<li>Execute:
	<pre>
/bin/bash enable-ssl.sh --all
	</pre>
	</li>
	<li>Start all services via Ambari, which is now running on port 8443</li>
	<li>Goto Ranger Admin UI and edit HDFS and HBase services to set the <em>Common Name for Certificate</em> to <em>$NAMENODE_SERVER_ONE</em> and <em>$HBASE_MASTER_SERVER_ONE</em> that you specified in the above script</li>
</ol>
<p>
	If you chose not to enable SSL for some components or decide to modify the script to include others (please send me a patch) then be aware of these dependencies:
</p>
<ul>
	<li>Setting up Ambari trust store is required before enabling SSL encryption for any other component</li>
	<li>Before you enable HBase SSL encryption, enable Hadoop SSL encryption</li>
</ul>
<h2>Validation tips</h2>
<ul>
	<li>View and verify SSL certificate being used by a server
	<pre>
openssl s_client -connect ${OOZIE_SERVER_ONE}:11443 -showcerts  &lt; /dev/null
	</pre>
	</li>
	<li>
	View Oozie jobs through command-line
	<pre>
oozie jobs -oozie  https://${OOZIE_SERVER_ONE}:11443/oozie
	</pre>
	</li>
	<li>View certificates stored in a Java keystore
	<pre>
keytool -list -storepass password -keystore /etc/hadoop/conf/hadoop-private-keystore.jks
	</pre>
	</li>
	<li>View Ranger policies for HDFS
	<pre>
cat example1.hortonworks.com.key example1.hortonworks.com.crt  &gt;&gt; example1.hortonworks.com.pem
curl --cacert /tmp/security/ca.crt --cert /tmp/security/example1.hortonworks.com.pem "https://example1.hortonworks.com:6182/service/plugins/policies/download/cluster1_hadoop?lastKnownVersion=3&pluginId=hdfs@example1.hortonworks.com-cluster1_hadoop"
	</pre>
	</li>
	<li>
	Validate that Ranger plugins can connect to Ranger admin server by searching for <em>util.PolicyRefresher</em> in HDFS NameNode and HBase RegionServer log files
	</li>
</ul>
<h2>References</h2>
<ul>
	<li><a href="https://github.com/vzlatkin/EnableSSLinHDP">GitHub repo</a></li>
	<li><a href="https://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.4.0/bk_Security_Guide/content/set_up_ssl_for_ambari.html">Documentation to enable SSL for Ambari</a></li>
	<li><a href="https://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.4.0/bk_Security_Guide/content/ch_wire-oozie.html">Oozie HDP documentation</a> and <a href="https://oozie.apache.org/docs/4.1.0/AG_Install.html#To_use_a_Certificate_from_a_Certificate_Authority">Oozie documentation on apache.org</a></li>
	<li><a href="https://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.4.0/bk_Security_Guide/content/ch_wire-webhdfs-mr-yarn.html">Enable SSL encryption for Hadoop components</a></li>
	<li><a href="https://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.4.0/bk_Security_Guide/content/configure_ambari_ranger_ssl_public_ca_certs.html">Documentation for Ranger</a></li>
</ul>