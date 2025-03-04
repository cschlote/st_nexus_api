/** This is the Nexus-Zipper utility
 *
 * Authors: Carsten Schlote <schlote@vahanus.net>
 * Copyright: 2018-2025 by Carsten Schlote
 * License: GPL3, All rights reserved
 */
module appZipper;

import std.conv;
import std.datetime;
import std.exception;
import std.json;
import std.range;
import std.stdio;
import std.string;
import std.zip;

import logging;
import nexus_api_io;
import nexus_api_ops;
import std.regex;
import std.bitmanip;

/** return a Duration from a human readable string
 *
 * The string is a number. Optionally a unit suffix may follow : w, d, h, m (Week,Day,Hour,Minute).
 * any other suffix or no suffix defaults as a second
 *
 * Params:
 *   age = a humanreable duration string, with optional w, d, h, m unit as suffix.
 * Returns:
 *   A Duration value
 */
Duration getDurationFromString(string age)
{
    import core.time;

    Duration d = Duration.zero;
    age = age.strip;

    long ageval = 0;
    try
    {
        ageval = age.parse!long;
    }
    catch (ConvException)
    {
        logFLine("Can't convert '%s' to long", age);
    }

    if (age.endsWith("w"))
        d = dur!"weeks"(ageval);
    else if (age.endsWith("d"))
        d = dur!"days"(ageval);
    else if (age.endsWith("h"))
        d = dur!"hours"(ageval);
    else if (age.endsWith("m"))
        d = dur!"minutes"(ageval);
    else
        d = dur!"seconds"(ageval);
    return d;
}

@("Test getDurationFromString()")
unittest
{
    assert(getDurationFromString("1") == dur!"seconds"(1));
    assert(getDurationFromString("1s") == dur!"seconds"(1));
    assert(getDurationFromString("1m") == dur!"minutes"(1));
    assert(getDurationFromString("1h") == dur!"hours"(1));
    assert(getDurationFromString("1w") == dur!"weeks"(1));
}

/** Returns a DateTime from a ISO time string
 *
 * Params:
 *   extiso = An suspected ISO time string
 * Returns:
 *   DateTime from string, or DateTime(1, 1, 1);
 */
DateTime getDataTimeFromExtISOFormat(string extiso)
{
    DateTime datetime = DateTime(1, 1, 1);
    try
    {
        datetime = SysTime.fromISOExtString(extiso).to!DateTime;
    }
    catch (TimeException e)
    {
        // logFLine("Can't parse download time %s\n%s", extiso, e.msg);
    }
    return datetime;
}

@("Testing getDataTimeFromExtISOFormat()")
unittest
{
    assert(getDataTimeFromExtISOFormat("1") == DateTime(1, 1, 1));
    assert(getDataTimeFromExtISOFormat("2024-03-22T09:09:01") == DateTime(2024, 3, 22, 9, 9, 1));
    assert(getDataTimeFromExtISOFormat("2024-03-22T09:09:01.246+00:00") == DateTime(2024, 3, 22, 9, 9, 1));

}

/** From a NxComponent return the Duration from last access and relevant dates
 *
 * Params:
 *   nxc = NxComponent
 *   crtTime = CreationTime
 *   dldTime = LastDownloadTime
 *   modTime = Modification Time
 *   lstTime = Date of last download or modification
 * Returns:
 *   Duration to date of last access
 */
Duration getNoAccessDuration(NxComponent nxc, ref DateTime crtTime, ref DateTime dldTime, ref DateTime modTime, ref DateTime lstTime)
{
    if (nxc.assets.length != 0)
    {
        import std.algorithm.comparison : max;
        import std.datetime.systime : SysTime, Clock;

        SysTime currentTime = Clock.currTime();
        DateTime nowTime = currentTime.to!DateTime;

        crtTime = getDataTimeFromExtISOFormat(nxc.assets[0].blobCreated);
        dldTime = getDataTimeFromExtISOFormat(nxc.assets[0].lastDownloaded);
        modTime = getDataTimeFromExtISOFormat(nxc.assets[0].lastModified);

        lstTime = max(dldTime, modTime);

        Duration holdTime = nowTime - lstTime;
        return holdTime;
    }
    return Duration.zero;
}

@("Testing getNoAccessDuration()")
unittest
{
    // Create mock NxComponent
    NxComponent component = NxComponent(
id : "test-id",
repository:
        "TestRepo",
format:
        "raw",
group:
        "/Data",
name:
        "Data/TestFile.zip",
version_:
        "1.0",
assets:
        [
        NxAsset(
blobCreated : "2023-01-01T00:00:00Z",
lastDownloaded:
            "2023-01-05T00:00:00Z",
lastModified:
            "2023-01-10T00:00:00Z"
        )
    ]
    );

    DateTime crtTime;
    DateTime dldTime;
    DateTime modTime;
    DateTime lstTime;

    Duration duration = getNoAccessDuration(component, crtTime, dldTime, modTime, lstTime);

    // Get current time for comparison
    SysTime currentTime = Clock.currTime();
    DateTime nowTime = currentTime.to!DateTime;

    // Assert the expected values
    assert(crtTime == SysTime.fromISOExtString("2023-01-01T00:00:00Z").to!DateTime);
    assert(dldTime == SysTime.fromISOExtString("2023-01-05T00:00:00Z").to!DateTime);
    assert(modTime == SysTime.fromISOExtString("2023-01-10T00:00:00Z").to!DateTime);
    assert(lstTime == SysTime.fromISOExtString("2023-01-10T00:00:00Z").to!DateTime);

    Duration expectedDuration = nowTime - lstTime;
    assert(duration == expectedDuration, text("duration:", duration, " expect:", expectedDuration));
}

/** Group array into components
 *
 * For the integrator we have special file format, which can be separated with '_'.
 * When
 *
 * Params:
 *   nxcs = NxComponents
 *   groupFilesBy = String which separates the filenames into at least 2 parts
 * Returns:
 *   A wrapped nxcomponent, either for a single 'ungrouped' group, or the grouped filename part.
 */
NxComponent[][string] groupNxComponents(NxComponent[] nxcs, string groupFilesBy)
{
    NxComponent[][string] groupedFiles;
    if (groupFilesBy.empty)
        groupedFiles["ungrouped"] = nxcs;
    else
    {
        foreach (nxc; nxcs)
        {
            auto splittedFileName = nxc.name.split(groupFilesBy);
            enforce(splittedFileName.length > 1, text("No split found for ", nxc.name, " ", groupFilesBy));
            groupedFiles[splittedFileName[0]] ~= nxc;
        }
    }
    return groupedFiles;
}

/** Zip a Nexus Repository/Path into a ZIP file
 *
 * Params:
 *   argServerURL = The base URL of the server
 *   argNXRpositoryName = The name of the nexus repository
 *   argNXPath = The path inside of the nexus repository
 *   argOutputZipFile = The output zip file
 * Returns:
 *   True
 * Throws:
 *   Exceptions from errors.
 */
bool runZipper(string argServerURL, string argNXRpositoryName, string argNXPath, string argOutputZipFile,
    bool argKeepPaths,
    string argUser, string argPasswd)
{
    import std.array : array;
    import std.file : write;
    import std.path : buildPath;
    import std.process : environment;
    import std.algorithm.iteration : filter;
    import std.algorithm.sorting : sort;
    import std.zip : ZipArchive;
    import requests.streams : ConnectError;

    // Set environment to override config
    auto server = environment.get("NX_SERVER", argServerURL);
    auto repo = environment.get("NX_REPOSITORY", argNXRpositoryName.length == 0 ? "TestRepo"
            : argNXRpositoryName);
    auto path = environment.get("NX_PATH", argNXPath.length == 0 ? "/" : argNXPath);
    auto user = environment.get("NX_USER", argUser);
    auto passwd = environment.get("NX_PASSWORD", argPasswd);

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
    assert(jsonObj.type == JSONType.object);

    assert(server, "Need at least a NX repository name");

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
        if (argKeepPaths)
            file1.name = key.name;
        else
            file1.name = key.name.split("/").back;
        file1.expandedData(cast(ubyte[]) data);

        zip.addMember(file1);
    }
    logFLine("Building ZIP file '%s'", argOutputZipFile);
    void[] compressed_data = zip.build();
    logFLine("Writing ZIP file '%s'", argOutputZipFile);
    assert(compressed_data.length != 0, "No data in ZIP?");
    write(argOutputZipFile, compressed_data);

    logLine("Finished zipper job.");
    return true;
}

@("Testing zipper operation")
unittest
{
    import std.exception : assertNotThrown;
    import std.file : exists;

    //nxobj.uploadNexusComponent("/Test-Autogen", filename, "Lorem ipsum...", "text/plain");

    bool rc;
    assertNotThrown(rc = runZipper("http://localhost:8081", "TestRepo", "/Data", "test.zip", "admin", "admin123"));
}
