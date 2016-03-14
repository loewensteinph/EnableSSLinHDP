<h1>Summary</h1>
Enabling SSL encryption for the Web UIs that make up Hadoop is a tedious process that requires planning, learning to use security tools, and lots of mouse clicks through Ambari's UI.  This article aims to simplify the process by presenting a semi-automated, start-to-finish example that enables SSL for the below Web UIs in the Hortonworks Sandbox:
<ol>
<li>Ambari</li>
<li>HBase</li>
<li>Oozie</li>
<li>Ranger</li>
<li>HDFS</li>
<li>YARN</li>
</ol>
<h2>Planning</h2>
There is no substitute for reading the <a href="http://docs.hortonworks.com">documentation</a>.  If you plan on enabling SSL in a production cluster, then make sure you are familiar with SSL concepts and the communication paths between each HDP component.  In addition, plan on cluster downtime.  You should know the role of each of the below components:
<ol>
<li><strong>Certificate Authority (CA)</strong></li>
<p>A Certificate Authority is a company that others trust that signs certificates for a fee.  On a Mac you can view a list of CAs that your computer trusts by opening up the Keychain Access application and clicking on System Roots.  If you don't want to pay one of these companies to sign your certificates, then you can generate your own CA, just beware the Google Chrome and other browsers will present you with a privacy warning.</p>
<li><strong>Server SSL certificate</strong></li>
<p>These are files that prove the identity of a something, in our case HDP services.  Usually there is one certificate per hostname, and it is signed by a CA.  There are two pieces of a certificate: the private and public keys.  A private key is needed to create and encrypt a message and a public certificate is needed to decrypt a message.  In a production cluster, each hostname will need a server SSL certificate</p>
<li><strong>Java private keystore</strong></li>
<p>When Java HDP services need to encrypt messages, they need a place to look for the private key part of a server's SSL certificate.  This keystore holds those private keys.  It should be kept secure so that no attacker could impersonate the service.  For this reason, each HDP component in this article has its own private keystore.</p>
<li><strong>Java trust keystore</strong></li>
<p>Just like my Mac has a list of CAs that it trusts, a Java process on a Linux machine needs the same.  This keystore will usually hold the CA certificate.  If the certificate was signed with a CA you generated then also add the public part of a server's SSL certificate into this keystore.</p>
<li><strong>Ranger plugins</strong></li>
<p>Ranger plugins communicate with Ranger Admin server over SSL.  What is important to understand is where each plugin executes and thus where server SSL certificates are needed.  For HDFS, the execution is on the NameNodes, for HBase, it is on the RegionServers, for YARN, it is on the ResourceManagers.</p>
</ol>
<h2>Enable SSL on HDP Sandbox</h2>
<p>
This part is rather easy.  Install the HDP 2.4 Sandbox and follow the below steps.  If you use an older version of the Sandbox note that you'll need to change the Ambari password used in the script.
<ol>
<li>Download a script from <a href="https://github.com/vzlatkin/EnableSSLinHDP">enable SSL in HDP</a> GitHub repository</li>
<li>Stop all services via Ambari</li>
<li>Execute:
<pre>
/bin/bash enable-ssl.sh --all
</pre>
</li>
<li>Edit <em>oozie-env</em> in Ambari and add to the end of <em>oozie-env template</em>:
<pre>
export OOZIE_HTTP_PORT=11000
export OOZIE_HTTPS_PORT=11443
</pre>
</li>
<li>Start all services via Ambari</li>
</ol>
<h2>Enable SSL in production</h2>
<p>
SSL encryption for a cluster is much harder to do than for a single machine Sandbox because there are many more certificates that need to be generated and the web of trust is more difficult to visualize.  Use the below notes, the <a href="https://github.com/vzlatkin/EnableSSLinHDP/blob/master/enable-ssl.sh">source code</a> to the above script, and the HDP <a href="http://docs.hortonworks.com">documentation</a> to make the process simpler.  The below assumes that you are using a public CA to sign your certificates, therefore, you'll have to use FQDN in all server certificates, but won't need to add the public certificate into Java's trust keystore.
</p>
<h3>Ambari</h3>
Enabling SSL encryption for Ambari is simplest; it is documented <a href="https://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.4.0/bk_Security_Guide/content/set_up_ssl_for_ambari.html">here</a>.  You need three files in advance: private key for Ambari server's SSL certificate, public key for the same, and the CA certificate.  Import the last two into a Java trust store, using <em>keytool</em> command.  You can either create a new store that is specific for Ambari or import into the default store that comes with RHEL: <em>/etc/pki/java/cacerts</em>.  Lastly, you'll execute <em>ambari-server</em> to enable HTTPS and configure a trust store.  See <a href="https://github.com/vzlatkin/EnableSSLinHDP/blob/master/enable-ssl.sh#L302">ambariSSLEnable()</a> function in the script for an automated example.
<h3>Oozie</h3>
Next easiest component for which to enable SSL encryption is Oozie.  Before starting you'll need to enable Ambari SSL (above), and have on hand the public and private keys of Oozie server's SSL certificate, and the CA certificate.  In addition, stop Oozie before proceeding and read the <a href="https://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.4.0/bk_Security_Guide/content/ch_wire-oozie.html">documentation</a>.  Mimic the commands in the script to create a Java private keystore in the <em>oozie</em> user's home directory using <em>keytool</em>, then add CA certificate into a Java trust store of your choice.  Again, either create a new one or use the default: <em>/etc/pki/java/cacerts</em>.  The script uses the latter.  Next, add OOZIE_HTTP_PORT and OOZIE_HTTPS_PORT variables to <em>oozie-env template</em> as mentioned above and restart the Oozie service via Ambari.  You can validate success by checking for errors in:
<pre>
openssl s_client -connect ${OOZIE_SERVER}:11443 -showcerts
</pre>
For the actual commands see <a href="https://github.com/vzlatkin/EnableSSLinHDP/blob/master/enable-ssl.sh#L285">oozieSSLEnable()</a> function.
<h3>Hadoop</h3>
This will enable SSL encryption for the following UIs: HDFS NameNode, YARN Resource Manager, YARN Application Timeline Server, and HDFS Journal Node. The <a href="https://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.4.0/bk_Security_Guide/content/ch_wire-webhdfs-mr-yarn.html">documentation</a> to enable is a little more complex, but the concepts are the same.  Just like above, each server with a Web UI needs three things: the server's SSL private key, public key, and the CA certificate.  In the script, all three pieces are generated in <a href="https://github.com/vzlatkin/EnableSSLinHDP/blob/master/enable-ssl.sh#L27">generateSSLCerts()</a> function.  In addition, each server needs to be able to find the private key for its SSL certificate it its private keystore and it needs to trust the CA.  Before you enable SSL for Hadoop's UIs be sure to enable SSL for Ambari (above) and stop the relevant components.  An example of each step is in <a href="https://github.com/vzlatkin/EnableSSLinHDP/blob/master/enable-ssl.sh#L131">hadoopSSLEnable()</a> function, you just need to restart the HDP components at the end.

<h3>HBase</h3>
Enabling SSL encryption for HBase Master UI requires changing only one configuration paramter: <em>hbase.ssl.enabled</em>.  In advance, you'll need to stop the service, enable Hadoop SSL, enable Ambari SSL (both above), and procure a signed SSL certificate for the HBase Master server.  Actual commands are listed in <a href="https://github.com/vzlatkin/EnableSSLinHDP/blob/master/enable-ssl.sh#L180">hbaseSSLEnable()</a> function.

<h3>Ranger</h3>
Configuring SSL for Ranger Admin UI is the <a href="https://docs.hortonworks.com/HDPDocuments/HDP2/HDP-2.4.0/bk_Security_Guide/content/configure_ambari_ranger_ssl_public_ca_certs.html">hardest</a> because you have to enable SSL for all Ranger related components: Admin UI, usersync, and each plugin.  For each enabled plugin, you'll need SSL certificates.  If you use HA for any component than you need a single certificate with a Common Name (CN) of one of the hosts.  In the <a href="https://github.com/vzlatkin/EnableSSLinHDP/blob/master/enable-ssl.sh#L212">script</a> I use <em>rangerHDFSAgent</em> and <em>rangerHBaseAgent</em> as the CNs, but that will not be possible if you use a public CA to sign your certificates.  The trust store on all servers will need to contain the CA used to sign the certificates.  Enabling Ambari SSL (above) is a prerequisite as is stopping HDFS, HBase, and Ranger.  After completion, you'll need to set the <b>Common Name For Certificate</b> to the CN in the Ranger Policy Manager UI.