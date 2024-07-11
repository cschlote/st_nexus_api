/** This is the Nexus-Cleaner utility
 *
 * Authors: Carsten Schlote <schlote@vahanus.net>
 * Copyright: 2018-2024 by Carsten Schlote
 * License: GPL3, All rights reserved
 */
module appCleaner;

import std.conv;
import std.datetime;
import std.exception;
import std.json;
import std.range;
import std.stdio;
import std.string;

import appConfig;

import logging;
import nexus_api_io;
import nexus_api_ops;
import std.regex;

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
    assert(duration == expectedDuration, text("duration:", duration, " expect:",expectedDuration));
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

/** Scan the Nexus Repositories from the config. Detect outdated files
 *
 * Params:
 *   nccObj = object containing the configuation from the JSOn config file
 *   argDeleteEntries = Really delete the expired files after the scan.
 *   argCacheFileName = Filename of a JSON file with the returned data
 *   reqFreeSize = 0 for all, otherwise stop cleaning after freeing reqFreeSize bytes of storage
 * Returns:
 *   True
 * Throws:
 *   Exceptions from errors.
 */
bool runCleaner(NexusCleanerConfig nccObj, bool argDeleteEntries, string argCacheFileName, size_t reqFreeSize)
{
    import std.array : array;
    import std.process : environment;
    import std.algorithm.iteration : filter;
    import std.algorithm.sorting : sort;
    import requests; //: ConnectError;

    // Set environment to override config
    auto server = environment.get("NX_SERVER", nccObj.serverUrl);
    auto user = environment.get("NX_USER");
    auto passwd = environment.get("NX_PASSWORD");

    auto nxobj = new NexusComponents();
    assert(nxobj !is null);

    nxobj.setUserCredentials(user, passwd);
    try
        nxobj.setServerUrl(server);
    catch (requests.streams.ConnectError)
        assert(false, "Network problem?");

    assert(nxobj.isValid() == true);

    assert(nxobj.getNXStatus() == true);
    assert(nxobj.getNXStatusWritable() == true);
    auto jsonObj = nxobj.getNXStatusCheck();
    assert(jsonObj.type == JSONType.object);

    NxComponent[] deleteNxComponents;

    assert(nccObj.repositories.length, "Need at least one repository");
    foreach (repoidx, repo; nccObj.repositories)
    {
        logFLine("Scanning Nexus repository '%s'", repo.nxRepository);

        nxobj.setRepository(repo.nxRepository);

        NxComponent[] nxcs;
        if (!argCacheFileName.empty)
            nxobj.restoreNexusComponents(argCacheFileName);

        nxcs = nxobj.getNexusComponents("", true);

        foreach (rulenr, rule; repo.nxRules)
        {
            logFLine("%02d:--- I Apply rules for group '%s'", rulenr, rule.group);
            auto matched = nxcs.filter!(a => a.group.startsWith(rule.group)).array;

            bool hasGroupedFiles = !rule.groupFilesBy.empty;
            NxComponent[][string] groupedMatches = groupNxComponents(matched, rule.groupFilesBy);
            foreach (grpIdx, grpKey; groupedMatches.keys)
            {
                if (hasGroupedFiles)
                    logFLine("%02d:--- I Files are grouped with key '%s'", rulenr, grpKey);

                auto minfiles = rule.minFiles != 0 ? rule.minFiles : repo.minFiles;
                auto holdMin = getDurationFromString(!rule.minAge.empty ? rule.minAge : repo.minAge);

                logFLine("%02d:--- I Defaults: minHold %s, minfiles %d", rulenr, holdMin, minfiles);

                NxComponent[] matchGroup = groupedMatches[grpKey];
                // Check for minimum number of elements in this file group
                if (matchGroup.length <= minfiles)
                {
                    logFLine("%02d:--- I Found %d entries within this group, but MinFile is %d. ", rulenr, matchGroup
                            .length, minfiles);
                    continue;
                }
                logFLine("%02d:--- I Found %d entries within this group", rulenr, matchGroup.length);

                // Sorted 
                auto sorted = matchGroup.sort!("a.name > b.name").array;
                foreach (idx, nxc; sorted)
                {
                    DateTime crtTime, dldTime, modTime, lstTime;
                    Duration holdTime = getNoAccessDuration(nxc, crtTime, dldTime, modTime, lstTime);

                    bool isExpired = (holdTime > holdMin);
                    char signer = isExpired ? 'D' : '=';
                    bool hasDownload = (dldTime != DateTime(1, 1, 1));

                    logFLine("%02d:%03d %c %-60s (Life: %s) (Rest: %s)", rulenr, idx, signer, nxc.name,
                        holdTime.total!"days", (holdMin - holdTime).total!"days");

                    logFLineVerbose("%02d:%03d %c crtTime=%-20s dldTime=%-20s, modTome=%-20s => lstTime=%s ", rulenr, idx, signer,
                        crtTime, (hasDownload ? dldTime.to!string : "--------------------"), modTime, lstTime, crtTime
                    );

                    if (isExpired)
                        deleteNxComponents ~= nxc;
                }
            } // matchGroup
        }
        logLine();
    }

    logLine("Finished scan job.");

    // Sort by idletime and size
    bool sortByNoAccessDurationAndSize(NxComponent a, NxComponent b)
    {
        DateTime crtTimeA, dldTimeA, modTimeA, lstTimeA;
        Duration holdTimeA = getNoAccessDuration(a, crtTimeA, dldTimeA, modTimeA, lstTimeA);
        DateTime crtTimeB, dldTimeB, modTimeB, lstTimeB;
        Duration holdTimeB = getNoAccessDuration(b, crtTimeB, dldTimeB, modTimeB, lstTimeB);
        bool isAOlder = holdTimeA.total!"days" > holdTimeB.total!"days"; // Oldest files first, day granularity!
        bool isSameAge = holdTimeA.total!"days" == holdTimeB.total!"days";
        bool isALarger = a.assets[0].fileSize > b.assets[0].fileSize;
        bool isASamgeAgeAndLarger = isSameAge && isALarger;

        return isAOlder || isASamgeAgeAndLarger;
    }

    bool filterByExistingDLTime(NxComponent a)
    {
        bool hasDLTime = getDataTimeFromExtISOFormat(a.assets[0].lastDownloaded) != DateTime(1, 1, 1);
        return hasDLTime;
    }

    bool filterByMissingDLTime(NxComponent a)
    {
        return !filterByExistingDLTime(a);
    }

    logFLine("We have %d components in expire list.", deleteNxComponents.length);

    auto deleteNxComponentsSorted = deleteNxComponents.sort!sortByNoAccessDurationAndSize;
    auto deleteNxComponentsNoDL = deleteNxComponentsSorted.filter!filterByMissingDLTime;
    auto deleteNxComponentsDL = deleteNxComponentsSorted.filter!filterByExistingDLTime;
    auto deleteNxComponentsNewOrder = chain(deleteNxComponentsNoDL, deleteNxComponentsDL);
    auto deleteNxComponentsOrdered = deleteNxComponentsNewOrder.enumerate;

    size_t allreadyFreed = 0;
    bool hasFreedEnough = false;

    logFLine("We are requested to free up to %d MiB of memory", reqFreeSize / 2 ^^ 20);
    logFLine("Deletion of files is %s", argDeleteEntries ? "enabled" : "disabled");

    foreach (idx, nxc; deleteNxComponentsOrdered)
    {
        DateTime crtTime, dldTime, modTime, lstTime;
        Duration holdTime = getNoAccessDuration(nxc, crtTime, dldTime, modTime, lstTime);
        hasFreedEnough = allreadyFreed >= reqFreeSize;
        char freedChar = hasFreedEnough ? '=' : 'D';
        logFLine("%c:%03d: %s", freedChar, idx, nxc.name);
        if (!hasFreedEnough)
        {
            if (argDeleteEntries)
                nxobj.deleteNexusComponent(nxc.id);
            allreadyFreed += nxc.assets[0].fileSize;
        }
        bool hasDLTime = getDataTimeFromExtISOFormat(nxc.assets[0].lastDownloaded) != DateTime(1, 1, 1);
        logFLine("%c:%03d: Size=%12d IdleAge:%s HasDLTime:%s", freedChar, idx,
            nxc.assets[0].fileSize, holdTime.total!"days", hasDLTime.to!string);

        hasFreedEnough = allreadyFreed > reqFreeSize;
        if (argDeleteEntries && hasFreedEnough)
        {
            logFLine("Freed %d MiB and more than requested %d MiB. We stop here.", allreadyFreed / 2 ^^ 20, reqFreeSize / 2 ^^ 20);
            break;
        }
    }

    if (!argCacheFileName.empty)
        nxobj.saveNexusComponents(argCacheFileName);

    if (!argDeleteEntries)
        logFLine("Total size of old files : %s MiB.", allreadyFreed / 2 ^^ 20);

    logLine("Finished clean job.");
    return hasFreedEnough;
}

@("Testing cleaner operation")
unittest
{
    import std.exception : assertNotThrown;
    import std.file : exists;

    NexusCleanerConfig nccObj = new NexusCleanerConfig;
    if (exists("tests/config.json"))
        nccObj.loadConfig("tests/config.json");
    else
        nccObj.loadConfig("tests/default.json");

    // nxobj.uploadNexusComponent("/Test-Autogen", filename, "Lorem ipsum...", "text/plain");

    bool rc;
    assertNotThrown(rc = runCleaner(nccObj, false, null, 0));
}
