/** Low-Level IO code for communication with the Sonytype Nexus API
 *
 * Authors: Carsten Schlote <schlote@vahanus.net>
 * Copyright: 2018-2024 by Carsten Schlote
 * License: GPL3, All rights reserved
 */
 module nexus_api_io;

import std.exception;
import std.conv;
import core.runtime;

/**
* Exception thrown on unrecoverable errors or enforce() asserts
*/
class NexusIOException : Exception
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

/** Construct the API URL from the parameters
 * 
 * Params:
 *   nxServer = server name, like "https://nexus.example.com"
 *   endPoint = The endpoint name, e.g. "assets", "components" or "status/check"
 *   repositoryName = Optional name of repository as argument
 *   contToken = Optional contToken for long responses
 * Returns: 
 *   Constructed string to access the Nexus API
 */
string getNexusAPIUrl(string nxServer, string endPoint, string repositoryName, string contToken = null) @trusted
{
    import std.range : appender, empty;
    import std.format : format;

    enforce!NexusIOException(nxServer !is null, "We need an URL string.");
    enforce!NexusIOException(!nxServer.empty, "We need a non-empty URL string.");
    enforce!NexusIOException(endPoint !is null, "We need an endpoint string.");
    enforce!NexusIOException(!endPoint.empty, "We need a non-empty endpoint string.");

    auto url = appender!string;
    url.reserve(256);

    url ~= format("%s/service/rest/v1/%s", nxServer, endPoint);

    char seperator = '?';
    if (!repositoryName.empty)
        url ~= format("%crepository=%s", seperator, repositoryName), seperator = '&';

    if (!contToken.empty)
        url ~= format("%ccontinuationToken=%s", seperator, contToken), seperator = '&';

    return url.data;
}

@("getNexusAPIUrl()")
unittest
{
    // string nexusURL = environment.get("NX_SERVER", "https://nexus.example.com");

    // Test basic URL construction
    assert(getNexusAPIUrl("https://nexus.example.com", "assets", "", "") ==
            "https://nexus.example.com/service/rest/v1/assets");

    // Test URL construction with repository name
    assert(getNexusAPIUrl("https://nexus.example.com", "components", "repo1", "") ==
            "https://nexus.example.com/service/rest/v1/components?repository=repo1");

    // Test URL construction with continuation token
    assert(getNexusAPIUrl("https://nexus.example.com", "status/check", "", "token123") ==
            "https://nexus.example.com/service/rest/v1/status/check?continuationToken=token123");

    // Test URL construction with both repository name and continuation token
    assert(getNexusAPIUrl("https://nexus.example.com", "assets", "repo1", "token123") ==
            "https://nexus.example.com/service/rest/v1/assets?repository=repo1&continuationToken=token123");

    // Test error when nxServer is null
    assertThrown!NexusIOException(getNexusAPIUrl(null, "assets", "", ""));

    // Test error when nxServer is empty
    assertThrown!NexusIOException(getNexusAPIUrl("", "assets", "", ""));
}

/** Download a JSON blob from a Nexus API URL
 *
 * Params:
 *   apiurl = Full API Url to access. Can be build with getNexusAPIUrl() method
 *   userName = name of API user
 *   passWord = password of API user
 * Returns:
 *   the JSON response
 * Throws: CURL or NexusIO exceptions on error
 */
string getJSONFromAPI(string webop = "GET")(string apiurl, string userName, string passWord, string payload = "") @trusted
in (apiurl !is null, "We need a apiurl string.")
{
    import std.conv : to;
    import std.exception : enforce;
    import std.process : environment;
    import std.format : format;
    import std.range : empty;

    assert(!apiurl.empty, "We need a non-empty apiurl string.");

    version (LibCurl)
    {
        pragma(msg, "NOTE: ", __PRETTY_FUNCTION__, " (LibCurl)");
        import std.net.curl : HTTP, get, CurlException;

        auto http = HTTP();
        http.setAuthentication(
            environment.get("NX_USER", userName),
            environment.get("NX_PASSWORD", passWord));
        http.addRequestHeader("accept", "application/json");
        http.verbose = false;

        /* Read the JSON file into memory, parse the contents */
        const auto jstr = get(apiurl, http);
        auto statusCode = http.statusLine.code;
        enforce!NexusIOException(statusCode / 100 == 2, "Failed to get JSON from url '%s'\n%s".format(apiurl, statusCode));
    }
    else version (DLangRequests)
    {
        pragma(msg, "NOTE: ", __PRETTY_FUNCTION__, " (Requests)");
        import requests : Request, Response, BasicAuthentication;

        auto rq = Request();
        rq.authenticator = new BasicAuthentication(
            environment.get("NX_USER", userName),
            environment.get("NX_PASSWORD", passWord));
        rq.addHeaders(["accept": "application/json"]);
        rq.verbosity = 0;
        static if (webop == "GET")
            auto rs = rq.get(apiurl);
        else static if (webop == "DELETE")
            auto rs = rq.deleteRequest(apiurl);
        else static if (webop == "PUT")
            auto rs = rq.put(apiurl, payload, "application/json");
        else static if (webop == "POST")
            auto rs = rq.post(apiurl, payload, "application/json");
        else
            pragma(msg, "Unknown webop");

        enforce!NexusIOException(rs.code / 100 == 2, "Failed to get JSON from url '%s'\n%s".format(apiurl, rq));

        auto jstr = cast(char[]) rs.responseBody.data;
    }
    else
        static assert(false, "Select the HTTP backend in dub.json");

    return jstr.to!string;
}

@("Testing download of JSON code from Nexus")
unittest
{
    import std.json : parseJSON, JSONValue;
    import std.exception : assertThrown, assertNotThrown;
    import std.process : environment;

    // import std.stdio : writeln;

    auto server = environment.get("NX_SERVER", "http://nexus.example.com");

    auto user = environment.get("NX_USER");
    auto paswd = environment.get("NX_PASSWORD");

    auto url = getNexusAPIUrl(server, "status", "", "");
    string jstr;

    assertNotThrown(jstr = getJSONFromAPI(url, user, paswd));
    assert(jstr is null, "No server message expected.");

    url = getNexusAPIUrl(server, "status/writable", "", "");
    assertNotThrown(jstr = getJSONFromAPI(url, user, paswd));
    assert(jstr is null, "No server message expected.");

    url = getNexusAPIUrl(server, "status/check", "", "");
    assertNotThrown(jstr = getJSONFromAPI(url, user, paswd));
    assert(jstr !is null, "Server message expected.");

    JSONValue j;
    assertNotThrown(j = parseJSON(jstr), "Can't parse returned data.");
    // writeln(j.toPrettyString);

    url = getNexusAPIUrl(server, "components", "NexusTest", "");
    assertNotThrown(getJSONFromAPI(url, user, paswd));
}

/** 
 * A Helper Structure to store multi-part form data
 */
struct NxFormData
{
    string name; /// A key name
    string value; /// A key value

    string filePath; /// path to data incl. filename
    string fileName; /// the filename to report
    string mimeType; /// the Mime-Type describing
}

/** Post a multipart form to the API
 * 
 * Params:
 *   apiurl = the full URL to access the Nexus API
 *   userName = empty or a username
 *   passWord = empty or a password
 *   formdata = an array of helper structures to encode the multipart message
 * Returns: 
 */
string postFormDataToAPI(string apiurl, string userName, string passWord, NxFormData[] formdata)
in (apiurl !is null, "We need a apiurl string.")
{
    import std.array : array;
    import std.conv : to;
    import std.exception : enforce;
    import std.process : environment;
    import std.format : format;
    import std.range : empty, appender;
    import std.outbuffer : OutBuffer;
    import std.string : startsWith, representation;

    import std.file : getcwd, read;
    import std.stdio : writeln;

    assert(!apiurl.empty, "We need a non-empty apiurl string.");

    version (LibCurl)
    {
        pragma(msg, "NOTE: ", __PRETTY_FUNCTION__, " (LibCurl)");
        import std.net.curl : HTTP, post;

        string boundary = "------------------------1BffcBhChZIcjL6WJnbyZy";

        auto http = HTTP();
        http.setAuthentication(
            environment.get("NX_USER", userName),
            environment.get("NX_PASSWORD", passWord));
        http.addRequestHeader("accept", "application/json");
        http.addRequestHeader("Content-Type", "multipart/form-data; boundary=" ~ boundary);
        http.verbose = false;

        auto multipartData = new OutBuffer();
        foreach (data; formdata)
        {
            if (!data.filePath.empty)
            {
                multipartData.write(boundary ~ "\r\n");
                multipartData.write(cast(ubyte[])(
                        "Content-Disposition: form-data; name=\"" ~ data.name ~ "\"\r\n"));
                multipartData.write("Content-Type: " ~ data.mimeType ~ "\r\n\r\n");
                if (data.filePath.startsWith("@"))
                    multipartData.write(cast(ubyte[])(std.file.read(data.filePath)));
                else
                    multipartData.write(cast(ubyte[])(data.filePath));
                multipartData.write("\r\n");
            }
            else
            {
                multipartData.write(boundary ~ "\r\n");
                multipartData.write(
                    "Content-Disposition: form-data; name=\"" ~ data.name ~ "\"\r\n\r\n");
                multipartData.write(data.value);
                multipartData.write("\r\n");
            }
        }
        multipartData.write(boundary ~ "\r\n");
        ubyte[] postdata = multipartData.data[0 .. multipartData.offset];
        // http.addRequestHeader("Content-Length",  postdata.length.to!string);

        std.file.write("payload.bin", postdata);

        /* Read the JSON file into memory, parse the contents */

        char[] jstr;
        try
        {
            jstr = post(apiurl, postdata, http);
        }
        catch (std.net.curl.HTTPStatusException)
        {

        }
        writeln(http.responseHeaders);

        auto statusCode = http.statusLine.code;
        enforce!NexusIOException(statusCode / 100 == 2, "Failed to get JSON from url '%s'\n%s".format(apiurl, statusCode));
    }
    else version (DLangRequests)
    {
        pragma(msg, "NOTE: ", __PRETTY_FUNCTION__, " (Requests)");
        import requests : Request, Response, BasicAuthentication, postContent, MultipartForm, formData;

        MultipartForm form;
        foreach (data; formdata)
        {
            if (!data.filePath.empty)
            {
                ubyte[] postdata;
                if (data.filePath.startsWith("@"))
                    postdata = cast(ubyte[])(read(data.filePath[1 .. $]));
                else
                    postdata = cast(ubyte[])(data.filePath);

                form.add(formData(data.name, postdata, [
                    "Content-Type": data.mimeType,
                    "name": data.name
                ]));
            }
            else
                form.add(formData(data.name, data.value));
        }

        // auto jstr = postContent(apiurl, form);
        auto rq = Request();
        rq.authenticator = new BasicAuthentication(
            environment.get("NX_USER", userName),
            environment.get("NX_PASSWORD", passWord));
        rq.addHeaders(["accept": "application/json"]);
        rq.verbosity = 0;

        auto rs = rq.post(apiurl, form);

        enforce!NexusIOException(rs.code / 100 == 2, "Failed to get JSON from url '%s'\n%s".format(apiurl, rq));

        auto jstr = cast(char[]) rs.responseBody.data;
        // writeln(rs.responseHeaders);
    }
    else
        static assert(false, "Select the HTTP backend in dub.json");

    return jstr.to!string;
}

@("Testing post of multi-part form to Nexus, e.g for uploads of components")
unittest
{
    import std.json : parseJSON, JSONValue, JSONType;
    import std.exception : assertThrown, assertNotThrown;
    import std.process : environment;

    // import std.stdio : writeln;

    auto userName = environment.get("NX_USER");
    auto passWord = environment.get("NX_PASSWORD");

    auto apiurl = "http://httpbin.org/post";
    string response;

    NxFormData[] formdata = [
        NxFormData("raw.directory", "/Test", "", "", ""),
        NxFormData("raw.asset1", "", "ABCDEF", "text.txt", "text/plain"),
        NxFormData("raw.asset1.filename", "text1.txt", "", "", ""),
        NxFormData("raw.asset2", "", "ABCDEF", "text.txt", "text/plain"),
        NxFormData("raw.asset2.filename", "text2.txt", "", "", "")
    ];
    response = postFormDataToAPI(apiurl, userName, passWord, formdata);
    // writeln(response);
    const auto jsonObj1 = response.parseJSON;
    assert(jsonObj1.type == JSONType.object, "Faulty response");
    

    auto server = environment.get("NX_SERVER", "http://nexus.example.com");
    apiurl = getNexusAPIUrl(server, "components", "NexusTest", "");
    // writeln(apiurl);

    NxFormData[] formdata2 = [
        NxFormData("raw.directory", "/Test", "", "", ""),
        NxFormData("raw.asset1", "", "@tests/gnulogo.png", "gnulogo.png", "image/png"),
        NxFormData("raw.asset1.filename", "gnulogo.png", "", "", ""),
        NxFormData("raw.asset2", "", "@tests/gnulogo.png", "gnulogo2.png", "image/png"),
        NxFormData("raw.asset2.filename", "gnulogo2.png", "", "", ""),
        NxFormData("raw.asset3", "", "ABCDEFGH", "test.txt", "text/plain"),
        NxFormData("raw.asset3.filename", "test.txt", "", "", "")
    ];
    response = postFormDataToAPI(apiurl, userName, passWord, formdata2);
    // writeln(response);
    assert(response.length == 0, "Unexpected response)");
}
