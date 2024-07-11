/** This is the Nexus-Cleaner utility, Filesystem Helper Module
 *
 * Authors: Carsten Schlote <schlote@vahanus.net>
 * Copyright: 2018-2024 by Carsten Schlote
 * License: GPL3, All rights reserved
 */
module helpers_filesystem;
import core.sys.posix.sys.statvfs;
import std.stdio;

struct FileSystemStats
{
    ulong freeSpace; // Free space in bytes
    ulong totalSpace; // Total space in bytes
}

FileSystemStats getFreeSpace(string mountPoint)
{
    statvfs_t fsStats;

    // Get filesystem statistics for the specified mount point
    if (statvfs64(mountPoint.ptr, &fsStats) != 0)
    {
        throw new Exception("Failed to get filesystem statistics for " ~ mountPoint);
    }

    FileSystemStats stats;
    stats.freeSpace = fsStats.f_bavail * fsStats.f_bsize;
    stats.totalSpace = fsStats.f_blocks * fsStats.f_bsize;
    return stats;
}

