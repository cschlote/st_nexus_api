/** This is the Nexus-Zipper utility
 *
 * Authors: Carsten Schlote <schlote@vahanus.net>
 * Copyright: 2018-2025 by Carsten Schlote
 * License: GPL3, All rights reserved
 */
module appZipper;

import std.exception;
import std.json;
import std.range;
import std.stdio;
import std.string;
import std.zip;

import logging;
import nexus_api_io;
import nexus_api_ops;

/** Zip a Nexus Repository/Path into a ZIP file
 *
 * Params:
 *   server = The base URL of the server
 *   repo = The name of the nexus repository
 *   path = The path inside of the nexus repository
 *   outputFilePath = The output zip file
 *   keepPaths = Keep the paths in the zip file
 *   user = The user name for the server
 *   passwd = The password for the server
 * Returns:
 *   True
 * Throws:
 *   Exceptions from errors.
 */
bool runZipper(string server, string repo, string path, string outputFilePath,
    bool keepPaths,
    string user, string passwd)
{
    import std.array : array;
    import std.file : write, mkdirRecurse;
    import std.path : buildPath, dirName;
    // import std.algorithm.iteration : filter;
    // import std.algorithm.sorting : sort;
    import std.zip : ZipArchive;
    import requests.streams : ConnectError;

    logLineVerbose("Server: ", server);
    logLineVerbose("Repository: ", repo);
    logLineVerbose("Path: ", path);
    logLineVerbose("User: ", user);
    logLineVerbose("Password: ", passwd);
    assert(server.length, "Need at least a NX server name");
    assert(repo.length, "Need at least a NX repository name");
    assert(path.length, "Need at least a NX path name");
    assert(user.length, "Need at least a NX user name");
    //assert(passwd.length, "Need at least a NX password");

    auto nxobj = new NexusComponents();
    assert(nxobj !is null);

    nxobj.setUserCredentials(user, passwd);
    try
        nxobj.setServerUrl(server);
    catch (ConnectError)
        assert(false, "Network problem?");

    assert(nxobj.isValid() == true);

    assert(nxobj.getNXStatus() == true);
    assert(nxobj.getNXStatusWritable() == true);
    auto jsonObj = nxobj.getNXStatusCheck();
    logFLineVerbose("Nexus status: %s", jsonObj);
    assert(jsonObj.type == JSONType.object, "No JSON object returned.");


    logFLine("Scanning Nexus server '%s'", server);
    logFLine("Scanning Nexus repository '%s'", repo);
    nxobj.setRepository(repo);

    NxComponent[] nxcs;
    logFLine("Scanning Nexus path '%s'", path);
    nxcs = nxobj.getNexusComponents(path, true);
    logFLine("Found %s components", nxcs.length);
    logLine("Finished scan job.");

    logFLine("Download and process files from Nexus path '%s'", path);

    auto zip = new ZipArchive();

    foreach (NxComponent key; nxcs)
    {
        logFLine("Processing '%s'", key.name);
        assert(key.assets.length != 0, "Can't process empty assets");
        // if (key.assets[0].fileSize > 10 * 1024 * 1024)
        //     continue; // Debug Aid! Skip large files

        logFLine("Downloading...");
        auto downloadUrl = key.assets[0].downloadUrl;
        enforce(downloadUrl.length != 0, format("  Can't download %s", key.assets[0].downloadUrl));
        enforce(downloadUrl.startsWith("http"), format("  Can't download %s", key
                .assets[0].downloadUrl));
        auto data = downloadFileFromNexus(downloadUrl, user, passwd);
        enforce(data.length != 0, format("Can't download '%s'", downloadUrl));
        logFLine("Downloaded %d bytes", data.length);
        assert(data.length == key.assets[0].fileSize, "Downloaded file size mismatch");

        logFLine("Adding data to zip archive.", key.name);
        ArchiveMember file1 = new ArchiveMember();
        if (!key.name.endsWith(".zip"))
            file1.compressionMethod = CompressionMethod.deflate;
        else
            file1.compressionMethod = CompressionMethod.none;
        if (keepPaths)
            file1.name = key.name;
        else
            file1.name = key.name.split("/").back;
        file1.expandedData(cast(ubyte[]) data);

        zip.addMember(file1);
    }
    logFLine("Building ZIP file '%s'", outputFilePath);
    void[] compressed_data = zip.build();
    logFLine("Writing ZIP file '%s'", outputFilePath);
    assert(compressed_data.length != 0, "No data in ZIP?");
    mkdirRecurse(outputFilePath.dirName);
    write(outputFilePath, compressed_data);

    logLine("Finished zipper job.");
    return true;
}

@("Testing zipper operation")
unittest
{
    import std.exception : assertNotThrown;
    import std.file : exists;

    bool rc;
    assertNotThrown(rc = runZipper("http://localhost:8081", "TestRepo", "/Data", "test.zip", "admin", "admin123"));
}
