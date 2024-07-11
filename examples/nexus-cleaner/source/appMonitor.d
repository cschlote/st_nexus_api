/** This is the Nexus-Cleaner utility, Config Module
 *
 * Authors: Carsten Schlote <schlote@vahanus.net>
 * Copyright: 2018-2024 by Carsten Schlote
 * License: GPL3, All rights reserved
 */

module appMonitor;

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

NxBlob[] getBlobSpaces(NexusCleanerConfig nccObj)
{
    import std.process : environment;
    import requests : ConnectError;

    auto server = environment.get("NX_SERVER", nccObj.serverUrl);
    auto user = environment.get("NX_USER");
    auto passwd = environment.get("NX_PASSWORD");

    auto nxobj = new NexusBlobs();
    assert(nxobj !is null);
    nxobj.setUserCredentials(user, passwd);
    try
        nxobj.setServerUrl(server);
    catch (ConnectError)
        assert(false, text("SRV:",server, " Network problem?"));

    NxBlob[] nxbs;
    nxbs = nxobj.getNexusBlobs();

    return nxbs;
}

@("Testing getBlobSpaces()")
unittest
{
    import std.exception : assertNotThrown;
    import std.file : exists;

    NexusCleanerConfig nccObj = new NexusCleanerConfig;
    if (exists("tests/config.json"))
        nccObj.loadConfig("tests/config.json");
    else
        nccObj.loadConfig("tests/default.json");

    NxBlob[] nxbs;
    nxbs = getBlobSpaces(nccObj);
    assert(nxbs !is null, "No blobs returned?");
    assert(nxbs.length > 0, "There should be at least one blobstore");
}

bool runMonitor(NexusCleanerConfig nccObj, int argMonitorLoopDelaySeconds, ref size_t reqFreeSize, bool noLoop = false)
{
    import std.process : environment;
    import requests : ConnectError;

    bool lowmem = false;
    NxBlob[] blobs;

    // Set environment to override config
    auto server = environment.get("NX_SERVER", nccObj.serverUrl);
    auto user = environment.get("NX_USER");
    auto passwd = environment.get("NX_PASSWORD");

    import helpers_filesystem : getFreeSpace;

    do
    {
        logLine("Checking free space");
        reqFreeSize = 0;
        if (nccObj.volumes.length)
        {
            foreach (vol; nccObj.volumes)
            {
                if (!vol.mountpoint.empty)
                {
                    auto stat = getFreeSpace(vol.mountpoint);

                    auto freeMB = stat.freeSpace / 2 ^^ 20;
                    if (freeMB <= vol.minFreeSize)
                    {
                        reqFreeSize = vol.minFreeSize - freeMB;
                        lowmem = true;
                    }
                    logFLine("%c Mountpoint:'%s' FreeMB:%d Limit:%d",
                        lowmem ? '!' : '-',
                        vol.mountpoint, freeMB, vol.minFreeSize);
                }
                if (!vol.blobstore.empty)
                {
                    if (blobs.length == 0)
                        blobs = getBlobSpaces(nccObj);
                    enforce(blobs.length, "No blobstores found on server.");
                    size_t freeMB = 0;
                    foreach (nxb; blobs)
                    {
                        if (nxb.name == vol.blobstore)
                        {
                            freeMB = nxb.availableSpaceInBytes / 2 ^^ 20;
                            break;
                        }
                    }
                    if (freeMB <= vol.minFreeSize)
                    {
                        reqFreeSize = vol.minFreeSize - freeMB;
                        lowmem = true;
                    }
                    logFLine("%c Blobstore:'%s' FreeMB:%d Limit:%d",
                        lowmem ? '!' : '-',
                        vol.blobstore, freeMB, vol.minFreeSize);
                }
            }

        }
        if (noLoop)
            break;
        if (lowmem)
        {
            logLine("Low memory situation. Exit monitor loop.");
        }
        else
        {
            logLine("No low memory situation. Lets idle some time and recheck.");

            logLine("Waiting ", argMonitorLoopDelaySeconds, " seconds");
            import core.thread.osthread : Thread;

            Thread.sleep(dur!("seconds")(argMonitorLoopDelaySeconds));
        }

    }
    while (lowmem == false);

    return lowmem;
}

@("Testing runMonitor()")
unittest
{
    import std.exception : assertNotThrown;
    import std.file : exists;

    NexusCleanerConfig nccObj = new NexusCleanerConfig;
    if (exists("tests/config.json"))
        nccObj.loadConfig("tests/config.json");
    else
        nccObj.loadConfig("tests/default.json");

    bool rc;
    size_t reqFreeSize;
    assertNotThrown(rc = runMonitor(nccObj, 60, reqFreeSize, true));
}
