/** Logging and Output Helpers
 *
 * This module contains code to log to stdout. Some versions output unconditionally, others
 * output only, if the 'verbose' flag was set on commandline. All outputs is flushed.
 *
 * Authors: Carsten Schlote <carsten.schlote@gmx.net>
 * Copyright: 2018-2023 by Carsten Schlote  
 * License: GPL3
 */
module logging;

import std.stdio : writeln, writefln, write, stdout;

/** Logging with format but no newline
 *
 * Params:
 *   args = args passed to writeln
 */
void logF(T...)(T args)
{
    version (unittest)
    {
    }
    else
    {
        writef(args);
        stdout.flush;
    }
}

/** Logging with format
 *
 * Params:
 *   args = args passed to writeln
 */
void logFLine(T...)(T args)
{
    version (unittest)
    {
    }
    else
    {
        writefln(args);
        stdout.flush;
    }
}

/** Logging without format
 *
 * Params:
 *   args = args passed to writeln
 */
void logLine(T...)(T args)
{
    version (unittest)
    {
    }
    else
    {
        writeln(args);
        stdout.flush;
    }
}

/** Logging without format and without newline
 *
 * Params:
 *   args = args passed to writeln
 */
void log(T...)(T args)
{
    version (unittest)
    {
    }
    else
    {
        write(args);
        stdout.flush;
    }
}

/** Logging with format and without newline, but only when verbose output is enabled
 *
 * Params:
 *   args = args passed to writeln
 */
void logFVerbose(T...)(T args)
{
    version (unittest)
    {
    }
    else
    {
        import app : argVerboseOutputs;

        if (argVerboseOutputs)
            writef(args);
        stdout.flush;
    }
}

/** Logging with format, but only when verbose output is enabled
 *
 * Params:
 *   args = args passed to writeln
 */
void logFLineVerbose(T...)(T args)
{
    version (unittest)
    {
    }
    else
    {
        import app : argVerboseOutputs;

        if (argVerboseOutputs)
            writefln(args);
        stdout.flush;
    }
}

/** Logging without format, but only when verbose output is enabled
 *
 * Params:
 *   args = args passed to writeln
 */
void logLineVerbose(T...)(T args)
{
    version (unittest)
    {
    }
    else
    {
        import app : argVerboseOutputs;

        if (argVerboseOutputs)
            writeln(args);
        stdout.flush;
    }
}

/** Logging without format and without newline, but only when verbose output is enabled
 *
 * Params:
 *   args = args passed to writeln
 */
void logVerbose(T...)(T args)
{
    version (unittest)
    {
    }
    else
    {
        import app : argVerboseOutputs;

        if (argVerboseOutputs)
        {
            write(args);
            stdout.flush;
        }
    }
}
