Tested on zabbix server 7.0.5 version

<body>
    <h1>Script Description</h1>
    <p>This script performs the following tasks:</p>
    <ol>
        <li><strong>Setup and Initialization:</strong>
            <ul>
                <li>Defines variables for Cloudflare API, Zabbix server, and authentication tokens.</li>            </ul>
        </li>
        <li><strong>Fetch All Domains:</strong>
            <ul>
                <li>Defines a function <code>get_all_zones</code> to fetch all domains associated with the Cloudflare account.</li>
                <li>Stores the fetched domains in an array <code>DOMAINS</code>.</li>
            </ul>
        </li>
        <li><strong>Loop Through Each Domain:</strong>
            <ul>
                <li>For each domain, it retrieves the Zone ID from Cloudflare.</li>
                <li>Lists DNS records for the domain and filters for A and CNAME records, saving them to <code>domain.txt</code>.</li>
            </ul>
        </li>
        <li><strong>Health Check for Each Domain:</strong>
            <ul>
                <li>Reads each domain from <code>domain.txt</code> and performs a health check by accessing the <code>/healthcheck</code> endpoint.</li>
                <li>If the response is "green", it saves the domain to <code>domain-exist.txt</code>.</li>
            </ul>
        </li>
        <li><strong>Create Web Scenarios in Zabbix:</strong>
            <ul>
                <li>Reads each domain from <code>domain-exist.txt</code> and checks if a web scenario already exists in Zabbix.</li>
                <li>If not, it creates a new web scenario for the domain with a health check step.</li>
            </ul>
        </li>
        <li><strong>Create Triggers in Zabbix:</strong>
            <ul>
                <li>Defines functions to get the host name by host ID and to create a trigger.</li>
                <li>Reads each domain from <code>domain-exist.txt</code> and creates a trigger in Zabbix if it doesn't already exist.</li>
            </ul>
        </li>
    </ol>
    <p>The script automates the process of fetching domains from Cloudflare, performing health checks, and setting up monitoring scenarios and triggers in Zabbix.</p>
</body>
