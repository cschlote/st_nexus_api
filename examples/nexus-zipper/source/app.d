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

import appZipper;
import logging;

bool argVerboseOutputs = false; /// Show detailed outputs

/** Zip Nexus Repository/Path
 * Params:
 *   args = string array with commandline args
 * Returns:
 *   a shell result code
 */
int main(string[] args)
{
	string argServerURL;
	string argNXRpositoryName;
	string argNXPath;
	string argOutputZipFile;
	bool argKeepPaths = false;
	string argUser;
	string argPassword;

	try
	{
		auto helpInformation = getopt(
			args,
			"server|s", "The base URL of the server", &argServerURL,
			"repository|r", "The name of the nexus repository", &argNXRpositoryName,
			"path|p", "The path inside of the nexus repository", &argNXPath,
			"output|o", "The output zip file", &argOutputZipFile,
			"keep-paths|k", "Keep the paths in the zip file", &argKeepPaths,
			"user|u", "The user name for the server", &argUser,
			"password", "The password for the server", &argPassword,
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

	logFLine("A Nexus-Zipper utility.\n");
	logLine("Build is ", import("GITTAG"), ", Arch is ", import("ARCH"));

	auto sw = StopWatch(AutoStart.no);
	sw.reset;
	sw.start;

	logFLine("NexusServer BaseURL : %s", argServerURL);

	succ = runZipper(argServerURL, argNXRpositoryName, argNXPath, argOutputZipFile, argKeepPaths, argUser, argPassword);

	sw.stop;
	logFLine("Total test duration: %s", sw.peek);

	int rc = succ ? 0 : 1;
	logFLine("Done. (rc=%d)", rc);
	return rc;
}
