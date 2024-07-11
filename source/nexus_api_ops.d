/** D implementations of Sonytype Nexus API Ops
 *
 * Authors: Carsten Schlote <schlote@vahanus.net>
 * Copyright: 2018-2024 by Carsten Schlote
 * License: GPL3, All rights reserved
 */
module nexus_api_ops;

import std.conv;
import std.exception;
import std.string;
import std.json;

import jsonizer;

import nexus_api_io;

/**
* Exception thrown on unrecoverable errors or enforce() asserts
*/
class NexusOpsException : Exception
{
    /// Constructor
    this(string msg, int line = 0, int pos = 0) pure nothrow @safe
    {
        if (line)
            super(text(msg, " (Line ", line, ":", pos, ")"));
        else
            super(msg);
    }
    /// Constructor
    this(string msg, string file, size_t line) pure nothrow @safe
    {
        super(msg, file, line);
    }
}

/** Nexus Email configuration 
 */
struct NxEmail
{
    mixin JsonizeMe; // this is required to support jsonization
    @jsonize
    { // public serialized members
        bool enabled; /// 
        string host; /// 
        int port; /// 
        string username; /// 
        string password; /// 
        string fromAddress; /// 
        string subjectPrefix; /// 
        bool startTlsEnabled; /// 
        bool startTlsRequired; /// 
        bool sslOnConnectEnabled; /// 
        bool sslServerIdentityCheckEnabled; /// 
        bool nexusTrustStoreEnabled; /// 
    }
}

/**
 * Checksum Data returned from Nexus Server
 */
struct NxChecksums
{
    mixin JsonizeMe; // this is required to support jsonization
    @jsonize
    { // public serialized members
        string sha1; /// 5c3bba2222dcccc3c4ba19ca25eaabfc417b34a1"
        string sha512; /// 64b1aaa18a17fd59d394ccd522e5d65456e2153004f640a70544e6b54ef8d91b175edfd697bc50a3dc5529989a9fac126e5f79be151cec0f186a89032126553d"
        string sha256; /// e6fb7633bfc7cffb48ff83185b7d632ba1eb9d7bfb532981f7b33c82d82f510d"
        string md5; /// 69652bcad1bc8f608d041f9d95b4abcf"
    }
}

/**
 * Asset Data returned from the Nexus server
 */
struct NxAsset
{
    mixin JsonizeMe; // this is required to support jsonization
    @jsonize
    { // public serialized members
        string downloadUrl; /// "https://nexus.example.com/repository/NexusTest/Data/YourFile.zip"
        string path; /// "Data/YourFile.zip"
        string id; /// bWFlc3RybzQtZGVwbG95bWVudHM6N2Y2Mzc5ZDMyZjhkZDc4Zjc3OWFhOTg4ODRmYmQzMmQ"
        string repository; /// NexusTest"
        string format; /// raw"
        string contentType; /// application/zip"
        string lastModified; /// 2022-07-28T12:49:52.634+00:00"
        string lastDownloaded; /// null
        string uploader; /// NexusTest"
        string uploaderIp; /// 172.29.147.131"
        ulong fileSize; /// 1708136
        string blobCreated; /// 2022-07-28T12:49:52.634+00:00
        NxChecksums checksum; /// A set of checksums
    }
}

/**
 * Component Data returned from the Nexus server
 */
struct NxComponent
{
    mixin JsonizeMe; // this is required to support jsonization
    @jsonize
    { // public serialized members
        string id; /// "bWFlc3RybzQtZGVwbG95bWVudHM6OTNiOWI5ZWI5YTdlY2IwNjE0OWVlODUwMTE5MTYxODQ"
        string repository; /// "NexusTest"
        string format; /// "raw"
        string group; /// "/Data"
        string name; /// "Data/YourFile.zip"
        string version_; /// null
        NxAsset[] assets; /// An array of NxAssets
    }
}

struct NxSoftQuota
{
    mixin JsonizeMe; // this is required to support jsonization
    @jsonize
    {
        string type; /// "spaceRemainingQuota",
        size_t limit; /// 1073741824
    }
}

struct NxBlob
{
    mixin JsonizeMe; // this is required to support jsonization
    @jsonize
    { // public serialized members
        NxSoftQuota softQuota; ///
        string name; /// "default",
        string type; /// "File",
        bool unavailable; /// false,
        long blobCount; /// 5506,
        size_t totalSizeInBytes; /// 379686054896,
        size_t availableSpaceInBytes; /// 130441445376
    }
}

/**
 * The base class of all Nexus API IO
 */
class NexusBase
{
private:
    string serverUrl; /// Name of the Server to connect to
    string repositoryName; /// Name of Nexus Repository

    string userName; /// Name of user to authenticate
    string passWord; /// Password of user to authenticate

public:
    //----------------------------------------------------------------------------

    /** Set the Nexus API Url
     *
     * Params:
     *   nexusUrl = e.g. "http://nexus.example.com"
     * Returns:
     *   true on sucess
     * Throws:
     *   NexusOpsException objects on own problems
     */
    bool setServerUrl(string nexusUrl) @safe
    {
        enforce!NexusOpsException(nexusUrl !is null, "We need an URL string.");
        enforce!NexusOpsException(!nexusUrl.empty, "We need a non-empty URL string.");

        serverUrl = nexusUrl;

        if (serverUrl !is null && !serverUrl.empty)
        {
            // try
            enforce!NexusOpsException(isValid(), "API URL not valid.");
            // catch (Exeception)
            // {

            // }

        }
        return true;
    }

    /** Get the Nexus API Url
     *
     * Returns:
     *   the API URL string
     */
    string getServerURL() const @safe
    {
        return serverUrl;
    }

    /** Set the Nexus Repository name
     *
     * Params:
     *   repoName = e.g. "NexusData", as specified on your Nexus server
     * Returns:
     *   true on sucess
     * Throws:
     *   NexusOpsException objects on own problems
     */
    bool setRepository(string repoName)
    {
        enforce!NexusOpsException(repoName !is null, "We need a repository string.");
        enforce!NexusOpsException(!repoName.empty, "We need a non-empty repository string.");

        repositoryName = repoName;
        return true;
    }

    /** Get the Nexus Repository name
     *
     * Returns:
     *   the API Repository name string
     */
    string getRepository() const @safe
    {
        return repositoryName;
    }

    /** Set the API User and Password for the API access
     *
     * Params:
     *   username = e.g. "foouser"
     *   password = e.g. "secret"
     * Returns:
     *   true on sucess
     * Throws:
     *   NexusOpsException objects on own problems
     */
    bool setUserCredentials(string username, string password)
    {
        enforce!NexusOpsException(username !is null, "We need an username string.");
        enforce!NexusOpsException(!username.empty, "We need a non-empty username string.");
        enforce!NexusOpsException(password !is null, "We need a passwd string.");
        enforce!NexusOpsException(!password.empty, "We need a non-empty passwd string.");
        userName = username;
        passWord = password;
        return true;
    }

    /** Get the Nexus User for the API access
     *
     * Returns:
     *   the username
     */
    string getUserName() const @safe
    {
        return userName;
    }

    /** Check the Nexus Repository user password
     *
     * Returns:
     *   true, if a password was set
     */
    bool hasUserPassword() const @safe
    {
        return (passWord !is null && passWord.empty == false);
    }

    /** Check, if the API connection is valid.
     *
     * Returns: true
     */
    bool isValid() @safe
    {
        return true;
    }
}

@("Testing class NexusBase")
unittest
{
    import std.process : environment;
    import std.exception : assertThrown, assertNotThrown;

    auto server = environment.get("NX_SERVER", "http://nexus.example.com");
    auto user = environment.get("NX_USER");
    auto passwd = environment.get("NX_PASSWORD");

    auto nxobj = new NexusBase();
    nxobj.setUserCredentials(user, passwd);
    nxobj.setServerUrl(server);
    nxobj.setRepository("NexusTest");

    assert(nxobj.getServerURL() == server);
    assert(nxobj.getRepository() == "NexusTest");
    assert(nxobj.getUserName() == user);
    assert(nxobj.hasUserPassword() == true);

    assert(nxobj.isValid() == true);
}

/** Add status API calls and basic network IO
 *
 */
class NexusStatus : NexusBase
{
private:

public:
    override bool isValid() @safe
    {
        return getNXStatus();
    }

    /** Test the status of the RO API
     * 
     * Returns: true, if connection is ok
     */
    bool getNXStatus() @safe
    {
        bool rc;
        auto url = getNexusAPIUrl(serverUrl, "status", "", "");
        try
        {
            auto jstr = getJSONFromAPI(url, userName, passWord);
            enforce!NexusOpsException(jstr is null, "No server data expected.");
            rc = true;
        }
        catch (NexusIOException)
        {
            rc = false;
        }
        return rc;
    }

    /** Test the status of the WR API
     * 
     * Returns: true, if connection is ok
     */
    bool getNXStatusWritable() @safe
    {
        bool rc;
        auto url = getNexusAPIUrl(serverUrl, "status/writable", "", "");
        try
        {
            auto jstr = getJSONFromAPI(url, userName, passWord);
            enforce!NexusOpsException(jstr is null, "No server data expected.");
            rc = true;
        }
        catch (NexusIOException)
        {
            rc = false;
        }
        return rc;

    }

    /** Get the status of several subsystems
     * 
     * Returns: true, if connection is ok
     */
    JSONValue getNXStatusCheck()
    {
        JSONValue jsonObj;
        auto url = getNexusAPIUrl(serverUrl, "status/check", "", "");
        try
        {
            auto jsonString = getJSONFromAPI(url, userName, passWord);
            enforce!NexusOpsException(jsonString !is null, "Server data expected.");

            jsonObj = parseJSON(jsonString);
            enforce!NexusOpsException(jsonObj.type == JSONType.object, "JSONObj for Server data expected.");
        }
        catch (NexusIOException)
        {

        }
        return jsonObj;
    }

    /*--------------------------------------------------------------------------*/

    bool getNexusEmail(ref NxEmail nxe)
    {
        bool rc;
        auto url = getNexusAPIUrl(serverUrl, "email", "", "");
        try
        {
            auto jsonString = getJSONFromAPI(url, userName, passWord);
            enforce!NexusOpsException(jsonString !is null, "No server data expected.");

            auto jsonValues = parseJSON(jsonString);
            enforce!NexusOpsException(jsonValues.type == JSONType.object, "JSONObj for Server data expected.");

            nxe = fromJSON!(NxEmail)(jsonValues);

            rc = true;
        }
        catch (NexusIOException)
        {
            rc = false;
        }
        return rc;
    }

    bool setNexusEmail(NxEmail nxe)
    {
        bool rc;
        auto url = getNexusAPIUrl(serverUrl, "email", "", "");
        try
        {
            auto nxeJSON = nxe.toJSON.toPrettyString;
            auto jsonString = getJSONFromAPI!"PUT"(url, userName, passWord, nxeJSON);
            enforce!NexusOpsException(jsonString is null, "No server data expected.");

            // auto jsonValues = parseJSON(jsonString);
            // enforce!NexusOpsException(jsonValues.type == JSONType.object, "JSONObj for Server data expected.");

            // nxe = fromJSON!(NxEmail)(jsonValues);

            rc = true;
        }
        catch (NexusIOException)
        {
            rc = false;
        }
        return rc;
    }

    /** Delete a single component to the server
     *
     * Params:
     *   id = the asset id
     */
    void deleteNexusEmail()
    {
        auto apiurl = getNexusAPIUrl(serverUrl, "email", "");
        const auto response = getJSONFromAPI!"DELETE"(apiurl, userName, passWord);
        assert(response.length == 0, "Unexpected response");
    }

    /** Verify a single component to the server
     *
     * Params:
     *   id = the asset id
     */
    bool verifydeleteNexusEmail(string email)
    {
        auto apiurl = getNexusAPIUrl(serverUrl, "email/verify", "");
        const auto jsonString = getJSONFromAPI!"POST"(apiurl, userName, passWord, email);
        assert(jsonString.length != 0, "Expected some response");

        auto jsonValues = parseJSON(jsonString);
        enforce!NexusOpsException(jsonValues.type == JSONType.object, "JSONObj for Server data expected.");
        enforce!NexusOpsException(("success" in jsonValues) !is null, "Missing 'success' bool.");
        enforce!NexusOpsException(("reason" in jsonValues) !is null, "Missing 'reason' string.");

        enforce!NexusOpsException(jsonValues["success"].boolean, text("Failed. Reason: ", jsonValues["reason"]
                .str));
        return true;
    }
}

@("Testing class NexusStatus")
unittest
{
    import std.process : environment;
    import std.exception : assertThrown, assertNotThrown;

    import requests : ConnectError;

    auto server = environment.get("NX_SERVER", "http://nexus.example.com");
    auto user = environment.get("NX_USER");
    auto passwd = environment.get("NX_PASSWORD");
    auto email = environment.get("NX_EMAIL", "user@example.com");

    auto nxobj = new NexusStatus();
    nxobj.setUserCredentials(user, passwd);
    try
        nxobj.setServerUrl(server);
    catch (ConnectError)
        assert(false, "Network problem?");
    nxobj.setRepository("NexusTest");

    assert(nxobj.getServerURL() == server);
    assert(nxobj.getRepository() == "NexusTest");
    assert(nxobj.getUserName() == user);
    assert(nxobj.hasUserPassword() == true);

    assert(nxobj.isValid() == true);

    assert(nxobj.getNXStatus() == true);
    assert(nxobj.getNXStatusWritable() == true);
    const auto jsonObj = nxobj.getNXStatusCheck();
    assert(jsonObj.type == JSONType.object);

    /*--------------------------------------------------*/
    NxEmail nxe, nxe2;
    auto rc = nxobj.getNexusEmail(nxe);
    if (rc)
    {
        version (DANGEROUS)
        {
            nxobj.deleteNexusEmail();
            rc = nxobj.getNexusEmail(nxe2);
            assert(rc == true);
            assert(nxe2.enabled == false);

            rc = nxobj.setNexusEmail(nxe);
            assert(rc == true);
            rc = nxobj.getNexusEmail(nxe2);
            assert(rc == true);
            assert(nxe == nxe2, "Data mismatch.");
        }

        nxobj.verifydeleteNexusEmail(email);
    }
}

/** Implementation of NexusBlobs class.
 */
class NexusAssets : NexusStatus
{
private:
    /// dynamic arrays of components, separated by Nexus repository name
    NxAsset[][string] nxAssets;

    void addUpdateNxAssets(NxAsset[] newcomps)
    {
        if (repositoryName in nxAssets)
        {
            outer: foreach (nc; newcomps)
            {
                foreach (oc; nxAssets[repositoryName])
                    if (nc.id == oc.id)
                    {
                        oc = nc;
                        continue outer;
                    }
                nxAssets[repositoryName] ~= nc;
            }
        }
        else
        {
            nxAssets[repositoryName] = newcomps;
        }
    }

public:
    /** Serialize the contents of NxAssets to a JSON file
    *
    * Params:
    *   fileName = filename of storage file
    */
    void saveNexusAssets(string fileName)
    {
        import std.file : write;

        const auto jsonValues = nxAssets.toJSON();
        auto jsonText = jsonValues.toPrettyString;
        write(fileName, jsonText);
    }

    /** Deserialize the contents from a JSON file to NxAssets
    *
    * Params:
    *   fileName = filename of storage file
    */
    void restoreNexusAssets(string fileName)
    {
        import std.file : readText, exists;
        import std.json : parseJSON;

        if (fileName.exists)
        {
            auto jsonText = readText(fileName);
            auto jsonValues = parseJSON(jsonText);
            nxAssets = fromJSON!(NxAsset[][string])(jsonValues);
        }
    }

    /** Clear the internally captured Component Data
     *
     */
    void clearNexusAssetCache()
    {
        nxAssets.clear();
    }

    /** Get dyn array of components of a Nexus Repository
     *
     * Returns:
     *   reference to dyn. array of components
     */
    NxAsset[] getNexusAssetCache()
    {
        return nxAssets[repositoryName];
    }

    /** Get assoc array of string indexed dyn arrays of components of a Nexus Repository
     *
     * Returns:
     *   reference to dyn. array of components
     */
    NxAsset[][string] getNexusAssetCacheAll()
    {
        return nxAssets;
    }

    /** Get all components from a Nexus server for a given Nexus repository and path
    *
    * The json format is described in the API section of the Nexus admin panel.
    *
    * Params:
    *   dirFilter = filter returned data by subdir
    *   forced_read = forced read from server instead of possible cache
    * Returns:
    *   An array of Nexus components converted from JSON to a D structure.
    */
    NxAsset[] getNexusAssets(string dirFilter = "", bool forced_read = false)
    {
        import std.array : array;
        import std.algorithm : filter;
        import jsonizer.fromjson : fromJSON;
        import std.json : JSONValue, parseJSON, JSONType;
        import std.range : empty;

        assert(!serverUrl.empty, "We need a Nexus server url");

        NxAsset[] nxc;

        if (forced_read || (repositoryName in nxAssets) is null)
        {
            // logFLine("        Download package list from Nexus repository '%s'", repositoryName);
            string contToken = "";
            do
            {
                auto apiurl = getNexusAPIUrl(serverUrl, "assets", repositoryName, contToken);

                auto jstr = getJSONFromAPI(apiurl, userName, passWord);
                JSONValue j = parseJSON(jstr);
                enforce!NexusOpsException("items" in j, "No 'items' array in JSON object");
                enforce!NexusOpsException("continuationToken" in j, "No continuationToken in JSON?");

                auto convertedData = j["items"].fromJSON!(NxAsset[]);
                if (!dirFilter.empty)
                {
                    auto matchedData = convertedData.filter!(x => x.path.startsWith(dirFilter))
                        .array;
                    nxc ~= matchedData;
                }
                else
                    nxc ~= convertedData;

                if (j["continuationToken"].type == JSONType.string)
                    contToken = j["continuationToken"].str;
                else
                    contToken = "";
            }
            while (!contToken.empty);

            addUpdateNxAssets(nxc);
            // NxAssets[nxrepository] = nxc;
        }
        else
        {
            nxc = nxAssets[repositoryName];
        }

        return nxc;
    }

    /** Query a single component on the server
     *
     * Params:
     *   id = the asset id
     *   asset = storage for the result
     * Returns:
     *   true if successful
     */
    bool getNexusAsset(string id, ref NxAsset asset)
    {
        auto apiurl = getNexusAPIUrl(serverUrl, "assets/" ~ id, "");
        auto response = getJSONFromAPI!"GET"(apiurl, userName, passWord);
        assert(response.length != 0, "Expected some response");
        JSONValue j = parseJSON(response);

        auto convertedData = j.fromJSON!(NxAsset);
        asset = convertedData;
        return true;
    }

    /** Delete a single component to the server
     *
     * Params:
     *   id = the asset id
     */
    void deleteNexusAsset(string id)
    {
        auto apiurl = getNexusAPIUrl(serverUrl, "assets/" ~ id, "");
        const auto response = getJSONFromAPI!"DELETE"(apiurl, userName, passWord);
        assert(response.length == 0, "Unexpected response");
    }
}

@("Testing class NexusAssets")
unittest
{
    import std.exception : assertThrown, assertNotThrown;
    import std.process : environment;
    import requests : ConnectError;

    auto server = environment.get("NX_SERVER", "http://nexus.example.com");
    auto user = environment.get("NX_USER");
    auto passwd = environment.get("NX_PASSWORD");

    auto nxobj = new NexusAssets();
    assert(nxobj !is null);
    nxobj.setUserCredentials(user, passwd);
    try
        nxobj.setServerUrl(server);
    catch (ConnectError)
        assert(false, "Network problem?");
    nxobj.setRepository("NexusTest");

    assert(nxobj.getServerURL() == server);
    assert(nxobj.getRepository() == "NexusTest");
    assert(nxobj.getUserName() == user);
    assert(nxobj.hasUserPassword() == true);

    assert(nxobj.isValid() == true);

    assert(nxobj.getNXStatus() == true);
    assert(nxobj.getNXStatusWritable() == true);
    const auto jsonObj = nxobj.getNXStatusCheck();
    assert(jsonObj.type == JSONType.object);

    NxAsset[] nxas;
    assertNotThrown(nxas = nxobj.getNexusAssets());
    assertNotThrown(nxas = nxobj.getNexusAssets("", true));
    assertNotThrown(nxas = nxobj.getNexusAssets());

    assertNotThrown(nxas = nxobj.getNexusAssets("/DirA"));
    assertNotThrown(nxas = nxobj.getNexusAssets("/DirA", true));
    assertNotThrown(nxas = nxobj.getNexusAssets("/DirA"));

    nxobj.saveNexusAssets("tests/nxassets.json");
    nxobj.clearNexusAssetCache();
    nxobj.restoreNexusAssets("tests/nxassets.json");

    nxas = nxobj.getNexusAssetCache();
    assert(nxas.length != 0);

    auto nxcsa = nxobj.getNexusAssetCacheAll();
    assert(nxcsa.length != 0);
    assert(nxcsa["NexusTest"].length != 0);

    /*-----------------------------------------*/
    /++
    enum int LOOPCNT = 99;
    enum string PATHPREFIX = "Test-Autogen-Assets";
    foreach (idx; 0 .. LOOPCNT)
    {
        string filename = text("testfile-", idx);
        nxobj.uploadNexusAsset(PATHPREFIX, filename, "Lorem ipsum...", "text/plain");
    }
    ++/
    /*-----------------------------------------*/
    assertNotThrown(nxas = nxobj.getNexusAssets("", true));
    NxAsset nxa;
    assertThrown(nxobj.getNexusAsset("4235235", nxa));

    /++
    /*-----------------------------------------*/
    foreach (nxc; nxcs)
    {
        if (nxc.path.startsWith(PATHPREFIX))
        {
            nxobj.deleteNexusAsset(nxc.id);
        }
    }
    ++/
}

/** Implementation of NexusComponents class.
 */
class NexusComponents : NexusStatus
{
private:
    /// dynamic arrays of components, separated by Nexus repository name
    NxComponent[][string] nxComponents;

    void addUpdateNxComponents(NxComponent[] newcomps)
    {
        if (repositoryName in nxComponents)
        {
            outer: foreach (nc; newcomps)
            {
                foreach (oc; nxComponents[repositoryName])
                    if (nc.id == oc.id)
                    {
                        oc = nc;
                        continue outer;
                    }
                nxComponents[repositoryName] ~= nc;
            }
        }
        else
        {
            nxComponents[repositoryName] = newcomps;
        }
    }

public:
    /** Serialize the contents of nxComponents to a JSON file
    *
    * Params:
    *   fileName = filename of storage file
    */
    void saveNexusComponents(string fileName)
    {
        import std.file : write;

        const auto jsonValues = nxComponents.toJSON();
        auto jsonText = jsonValues.toPrettyString;
        write(fileName, jsonText);
    }

    /** Deserialize the contents from a JSON file to nxComponents
    *
    * Params:
    *   fileName = filename of storage file
    */
    void restoreNexusComponents(string fileName)
    {
        import std.file : readText, exists;
        import std.json : parseJSON;

        if (fileName.exists)
        {
            auto jsonText = readText(fileName);
            auto jsonValues = parseJSON(jsonText);
            nxComponents = fromJSON!(NxComponent[][string])(jsonValues);
        }
    }

    /** Clear the internally captured Component Data
     *
     */
    void clearNexusComponentCache()
    {
        nxComponents.clear();
    }

    /** Get dyn array of components of a Nexus Repository
     *
     * Returns:
     *   reference to dyn. array of components
     */
    NxComponent[] getNexusComponentCache()
    {
        return nxComponents[repositoryName];
    }

    /** Get assoc array of string indexed dyn arrays of components of a Nexus Repository
     *
     * Returns:
     *   reference to dyn. array of components
     */
    NxComponent[][string] getNexusComponentCacheAll()
    {
        return nxComponents;
    }

    /** Get all components from a Nexus server for a given Nexus repository and path
    *
    * The json format is described in the API section of the Nexus admin panel.
    *
    * Params:
    *   dirFilter = filter returned data by subdir
    *   forced_read = forced read from server instead of possible cache
    * Returns:
    *   An array of Nexus components converted from JSON to a D structure.
    */
    NxComponent[] getNexusComponents(string dirFilter = "", bool forced_read = false)
    {
        import std.array : array;
        import std.algorithm : filter;
        import jsonizer.fromjson : fromJSON;
        import std.json : JSONValue, parseJSON, JSONType;
        import std.range : empty;

        assert(!serverUrl.empty, "We need a Nexus server url");

        NxComponent[] nxc;

        if (forced_read || (repositoryName in nxComponents) is null)
        {
            // logFLine("        Download package list from Nexus repository '%s'", repositoryName);
            string contToken = "";
            do
            {
                auto apiurl = getNexusAPIUrl(serverUrl, "components", repositoryName, contToken);

                auto jstr = getJSONFromAPI(apiurl, userName, passWord);
                JSONValue j = parseJSON(jstr);
                enforce!NexusOpsException("items" in j, "No 'items' array in JSON object");
                enforce!NexusOpsException("continuationToken" in j, "No continuationToken in JSON?");

                auto convertedData = j["items"].fromJSON!(NxComponent[]);
                if (!dirFilter.empty)
                {
                    auto matchedData = convertedData.filter!(x => x.group.startsWith(dirFilter))
                        .array;
                    nxc ~= matchedData;
                }
                else
                    nxc ~= convertedData;

                if (j["continuationToken"].type == JSONType.string)
                    contToken = j["continuationToken"].str;
                else
                    contToken = "";
            }
            while (!contToken.empty);

            addUpdateNxComponents(nxc);
            // nxComponents[nxrepository] = nxc;
        }
        else
        {
            nxc = nxComponents[repositoryName];
        }

        return nxc;
    }

    /** Upload a single component to the server
     *
     * Params:
     *   group = The Nexus group name
     *   name = filename to report
     *   data = the data or if prefixed with @ a file with the data
     *   mimetype = the MIME type of your data
     */
    void uploadNexusComponent(string group, string name, string data, string mimetype)
    {
        NxFormData[] formdata = [
            NxFormData("raw.directory", "/" ~ group, "", "", ""),
            NxFormData("raw.asset1", "", name, data, mimetype),
            NxFormData("raw.asset1.filename", name, "", "", "")
        ];
        auto apiurl = getNexusAPIUrl(serverUrl, "components", repositoryName);

        const auto response = postFormDataToAPI(apiurl, userName, passWord, formdata);
        assert(response.length == 0, "Unexpected response");
    }

    /** Delete a single component to the server
     *
     * Params:
     *   group = The Nexus group name
     *   name = filename to report
     *   data = the data or if prefixed with @ a file with the data
     *   mimetype = the MIME type of your data
     */
    void deleteNexusComponent(string id)
    {
        auto apiurl = getNexusAPIUrl(serverUrl, "components/" ~ id, repositoryName);
        const auto response = getJSONFromAPI!"DELETE"(apiurl, userName, passWord);
        assert(response.length == 0, "Unexpected response");
    }
}

@("Testing class NexusComponents")
unittest
{
    import std.exception : assertThrown, assertNotThrown;
    import std.process : environment;
    import requests : ConnectError;

    auto server = environment.get("NX_SERVER", "http://nexus.example.com");
    auto user = environment.get("NX_USER");
    auto passwd = environment.get("NX_PASSWORD");

    auto nxobj = new NexusComponents();
    assert(nxobj !is null);
    nxobj.setUserCredentials(user, passwd);
    try
        nxobj.setServerUrl(server);
    catch (ConnectError)
        assert(false, "Network problem?");
    nxobj.setRepository("NexusTest");

    assert(nxobj.getServerURL() == server);
    assert(nxobj.getRepository() == "NexusTest");
    assert(nxobj.getUserName() == user);
    assert(nxobj.hasUserPassword() == true);

    assert(nxobj.isValid() == true);

    assert(nxobj.getNXStatus() == true);
    assert(nxobj.getNXStatusWritable() == true);
    const auto jsonObj = nxobj.getNXStatusCheck();
    assert(jsonObj.type == JSONType.object);

    NxComponent[] nxcs;
    assertNotThrown(nxcs = nxobj.getNexusComponents());
    assertNotThrown(nxcs = nxobj.getNexusComponents("", true));
    assertNotThrown(nxcs = nxobj.getNexusComponents());

    assertNotThrown(nxcs = nxobj.getNexusComponents("/DirA"));
    assertNotThrown(nxcs = nxobj.getNexusComponents("/DirA", true));
    assertNotThrown(nxcs = nxobj.getNexusComponents("/DirA"));

    nxobj.saveNexusComponents("tests/nxcomponents.json");
    nxobj.clearNexusComponentCache();
    nxobj.restoreNexusComponents("tests/nxcomponents.json");

    nxcs = nxobj.getNexusComponentCache();
    assert(nxcs.length != 0);

    auto nxcsa = nxobj.getNexusComponentCacheAll();
    assert(nxcsa.length != 0);
    assert(nxcsa["NexusTest"].length != 0);

    /*-----------------------------------------*/
    enum int LOOPCNT = 99;
    enum string PATHPREFIX = "/Test-Autogen-Components";

    /*-----------------------------------------*/
    // Get asset level access objects here.
    auto nxast = new NexusAssets();
    assert(nxobj !is null);
    nxast.setUserCredentials(user, passwd);
    try
        nxast.setServerUrl(server);
    catch (ConnectError)
        assert(false, "Network problem?");
    nxast.setRepository("NexusTest");
    NxAsset[] nxas;

    /*-----------------------------------------*/
    foreach (idx; 0 .. LOOPCNT)
    {
        string filename = text("testfile-", idx);
        nxobj.uploadNexusComponent(PATHPREFIX, filename, "Lorem ipsum...", "text/plain");
    }
    /*-----------------------------------------*/
    assertNotThrown(nxcs = nxobj.getNexusComponents("", true));
    assertNotThrown(nxas = nxast.getNexusAssets("", true));

    /*-----------------------------------------*/
    foreach (idx, nxc; nxcs)
    {
        if (nxc.group.startsWith(PATHPREFIX))
        {
            NxAsset nxa;
            nxast.getNexusAsset(nxc.assets[0].id, nxa);
            assert(nxa == nxc.assets[0]);

            if ((idx & 1) == 1)
                nxobj.deleteNexusComponent(nxc.id);
            else
                nxast.deleteNexusAsset(nxc.assets[0].id);
        }
    }
    /*-----------------------------------------*/

}

/** Implementation of NexusBlobs class.
 */
class NexusBlobs : NexusStatus
{
private:
    /// dynamic arrays of blobstores
    NxBlob[] nxBlobs;

    void addUpdateNxBlobs(NxBlob[] newblobs)
    {
        if (nxBlobs.length)
        {
            outer: foreach (nc; newblobs)
            {
                foreach (oc; nxBlobs)
                    if (nc.name == oc.name)
                    {
                        oc = nc;
                        continue outer;
                    }
                nxBlobs ~= nc;
            }
        }
        else
        {
            nxBlobs = newblobs;
        }
    }

public:
    /** Serialize the contents of NxAssets to a JSON file
    *
    * Params:
    *   fileName = filename of storage file
    */
    void saveNexusBlobs(string fileName)
    {
        import std.file : write;

        const auto jsonValues = nxBlobs.toJSON();
        auto jsonText = jsonValues.toPrettyString;
        write(fileName, jsonText);
    }

    /** Deserialize the contents from a JSON file to NxAssets
    *
    * Params:
    *   fileName = filename of storage file
    */
    void restoreNexusBlobs(string fileName)
    {
        import std.file : readText, exists;
        import std.json : parseJSON;

        if (fileName.exists)
        {
            auto jsonText = readText(fileName);
            auto jsonValues = parseJSON(jsonText);
            nxBlobs = fromJSON!(NxBlob[])(jsonValues);
        }
    }

    /** Clear the internally captured Component Data
     *
     */
    void clearNexusBlobCache()
    {
        nxBlobs.length = 0;
    }

    /** Get assoc array of string indexed dyn arrays of components of a Nexus Repository
     *
     * Returns:
     *   reference to dyn. array of components
     */
    NxBlob[] getNexusBlobCache()
    {
        return nxBlobs;
    }

    /** Get all components from a Nexus server for a given Nexus repository and path
    *
    * The json format is described in the API section of the Nexus admin panel.
    *
    * Params:
    *   dirFilter = filter returned data by subdir
    *   forced_read = forced read from server instead of possible cache
    * Returns:
    *   An array of Nexus components converted from JSON to a D structure.
    */
    NxBlob[] getNexusBlobs(bool forced_read = false)
    {
        import std.array : array;
        import std.algorithm : filter;
        import jsonizer.fromjson : fromJSON;
        import std.json : JSONValue, parseJSON, JSONType;
        import std.range : empty;

        assert(!serverUrl.empty, "We need a Nexus server url");

        NxBlob[] nxb;

        if (forced_read || nxBlobs.length == 0)
        {
            // logFLine("        Download blobstore list");

            auto apiurl = getNexusAPIUrl(serverUrl, "blobstores", "", "");

            auto jstr = getJSONFromAPI(apiurl, userName, passWord);
            JSONValue j = parseJSON(jstr);
            enforce!NexusOpsException(j.type == JSONType.array, "No 'items' array in JSON object");

            auto convertedData = j.fromJSON!(NxBlob[]);
            nxb ~= convertedData;

            addUpdateNxBlobs(nxb);
        }
        else
        {
            nxb = nxBlobs;
        }

        return nxb;
    }

    /** Query a single component on the server
     *
     * Params:
     *   id = the asset id
     *   asset = storage for the result
     * Returns:
     *   true if successful
     */
//    bool getNexusBlob(string name, ref NxBlob nxblob)
//    {
//        auto apiurl = getNexusAPIUrl(serverUrl, "blobstores/" ~ name, "");
//        auto response = getJSONFromAPI!"GET"(apiurl, userName, passWord);
//        assert(response.length != 0, "Expected some response");
//        JSONValue j = parseJSON(response);
//
//        auto convertedData = j.fromJSON!(NxBlob);
//        nxblob = convertedData;
//        return true;
//    }

    /** Delete a single component to the server
     *
     * Params:
     *   id = the asset id
     */
    void deleteNexusBlob(string name)
    {
        auto apiurl = getNexusAPIUrl(serverUrl, "blobstores/" ~ name, "");
        const auto response = getJSONFromAPI!"DELETE"(apiurl, userName, passWord);
        assert(response.length == 0, "Unexpected response");
    }
}

@("Testing class NexusBlobs")
unittest
{
    import std.exception : assertThrown, assertNotThrown;
    import std.process : environment;
    import requests : ConnectError;

    auto server = environment.get("NX_SERVER", "http://nexus.example.com");
    auto user = environment.get("NX_USER");
    auto passwd = environment.get("NX_PASSWORD");

    auto nxobj = new NexusBlobs();
    assert(nxobj !is null);
    nxobj.setUserCredentials(user, passwd);
    try
        nxobj.setServerUrl(server);
    catch (ConnectError)
        assert(false, "Network problem?");
    nxobj.setRepository("NexusTest");

    assert(nxobj.getServerURL() == server);
    assert(nxobj.getRepository() == "NexusTest");
    assert(nxobj.getUserName() == user);
    assert(nxobj.hasUserPassword() == true);

    assert(nxobj.isValid() == true);

    assert(nxobj.getNXStatus() == true);
    assert(nxobj.getNXStatusWritable() == true);
    const auto jsonObj = nxobj.getNXStatusCheck();
    assert(jsonObj.type == JSONType.object);

    NxBlob[] nxbs;
    assertNotThrown(nxbs = nxobj.getNexusBlobs());
    assert(nxbs.length != 0, "Expected blobs");
    assertNotThrown(nxbs = nxobj.getNexusBlobs());
    assert(nxbs.length != 0, "Expected blobs");
    assertNotThrown(nxbs = nxobj.getNexusBlobs(true));
    assert(nxbs.length != 0, "Expected blobs");

    nxobj.saveNexusBlobs("tests/nxblobs.json");
    nxobj.clearNexusBlobCache();
    nxobj.restoreNexusBlobs("tests/nxblobs.json");

    nxbs = nxobj.getNexusBlobCache();
    assert(nxbs.length != 0);
    foreach (NxBlob nxb; nxbs)
    {
        assert(nxb.type == "File");
    }

}
