/** This is the Nexus-Cleaner utility.
 *
 * Authors: Carsten Schlote <schlote@vahanus.net>
 * Copyright: 2018-2024 by Carsten Schlote
 * License: GPL3, All rights reserved
 */
module app;

import std.conv;
import std.datetime.stopwatch;
import std.file;
import std.format;
import std.getopt;
import std.stdio;

import appCleaner;
import appConfig;
import appMonitor;
import helpers_filesystem;
import logging;

bool argVerboseOutputs = false; /// Show detailed outputs

/** Clean Nexus Repository by rules
 * Params:
 *   args = string array with commandline args
 * Returns:
 *   a shell result code
 */
int main(string[] args)
{
	string argConfigFileName;
	string argCacheFileName;
	bool argDeleteEntries;
	bool argMonitor;
	int argMonitorLoopDelaySeconds = 60;
	size_t argFreeSize = 0; // size_t.max / 2 ^^ 20;

	try
	{
		auto helpInformation = getopt(
			args,
			std.getopt.config.required,
			"config|c", "The config JSON file", &argConfigFileName,
			"cache|j", "Cache downloaded components", &argCacheFileName,
			"delete|d", "Delete outdated items", &argDeleteEntries,
			"monitor|m", "Monitor free memory and call on demand", &argMonitor,
			"monitortime|t", "Set looping interval in seconds", &argMonitorLoopDelaySeconds,
			"size|s", "Amount of MB memory to free", &argFreeSize,
			"verbose|v", "Verbose outputs (WIP)", &argVerboseOutputs
		);
		if (helpInformation.helpWanted)
		{
			defaultGetoptPrinter("Some information about the program.",
				helpInformation.options);
			return 0;
		}
	}
	catch (std.getopt.GetOptException goe)
	{
		logLine(goe.msg);
		return 1;
	}
	catch (std.conv.ConvException ce)
	{
		logLine(ce.msg);
		return 1;
	}

	bool succ = false;
	auto jcfg = new NexusCleanerConfig();

	logFLine("A Nexus-Cleaner utility.\n");
	logLine("Build is ", import("GITTAG"), ", Arch is ", import("ARCH"));

	auto sw = StopWatch(AutoStart.no);
	sw.reset;
	sw.start;

	logFLine("Loading configuration : %s", argConfigFileName);
	try
	{
		jcfg.loadConfig(argConfigFileName);
	}
	catch (Exception e)
	{
		logFLine("No config file found. (%s)", e.msg);
		jcfg.loadDefaults;
	}

	if (argMonitor)
	{
		while (true)
		{
			size_t reqMemSizeMB;
			succ = runMonitor(jcfg, argMonitorLoopDelaySeconds, reqMemSizeMB);
			if (succ)
			{
				succ = runCleaner(jcfg, argDeleteEntries, argCacheFileName, argFreeSize * 2 ^^ 20);
				if (succ)
					logLine("Resolved low memory situation");
				else
					logFLine("Can't free at least %d MiB of storage.", reqMemSizeMB);
			}
		}
	}
	else
		succ = runCleaner(jcfg, argDeleteEntries, argCacheFileName, argFreeSize * 2 ^^ 20);

	sw.stop;
	logFLine("Total test duration: %s", sw.peek);

	int rc = succ ? 0 : 1;
	logFLine("Done. (rc=%d)", rc);
	return rc;
}
