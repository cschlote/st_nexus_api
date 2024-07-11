/** This is the Nexus-Cleaner utility, Config Module
 *
 * Authors: Carsten Schlote <schlote@vahanus.net>
 * Copyright: 2018-2024 by Carsten Schlote
 * License: GPL3, All rights reserved
 */

module appConfig;

import std.json;
import std.file;

import jsonizer;

private struct NxCleanerConfigRule
{
    mixin JsonizeMe; // this is required to support jsonization
    @jsonize
    { // public serialized members
        string group;
        string minAge;
        int minFiles;
        string groupFilesBy;
    }
}

private struct NxCleanerConfigRepos
{
    mixin JsonizeMe; // this is required to support jsonization
    @jsonize
    { // public serialized members
        string minAge;
        int minFiles;
        string nxRepository;
        NxCleanerConfigRule[] nxRules;
    }
}

private struct NxCleanerConfigVols
{
    mixin JsonizeMe; // this is required to support jsonization
    @jsonize
    { // public serialized members
        int minFreeSize;
        string mountpoint;
        string blobstore;
    }
}

private struct NxCleanerConfig
{
    mixin JsonizeMe; // this is required to support jsonization
    @jsonize
    { // public serialized members
        NxCleanerConfigRepos[] repositories;
        string serverUrl;
        NxCleanerConfigVols[] volumes;
    }
}

immutable string defJson = import("tests/default.json");

class NexusCleanerConfig
{
    JSONValue jsonValues;

    NxCleanerConfig nxConfig;

    bool loadDefaults()
    {
        JSONValue defJObj = defJson.parseJSON();
        jsonValues = defJObj;
        nxConfig = fromJSON!(NxCleanerConfig)(jsonValues);
        return true;
    }

    bool loadConfig(string filename)
    {
        auto jsontext = readText(filename);
        jsonValues = parseJSON(jsontext);
        nxConfig = fromJSON!(NxCleanerConfig)(jsonValues);
        return true;
    }

    bool saveConfig(string filename)
    {
        auto jsonValues = nxConfig.toJSON;
        auto jsontext = jsonValues.toPrettyString;
        write(filename, jsontext);
        return true;
    }

    alias this = nxConfig;
}

@("Testing NexusCleanerConfig")
unittest
{
    import std.exception : assertNotThrown, assertThrown;

    auto nxccfg = new NexusCleanerConfig;

    assert(nxccfg.serverUrl == "");
    nxccfg.serverUrl = "http://nexus.example.com";
    assert(nxccfg.serverUrl == "http://nexus.example.com");

    nxccfg.loadDefaults();
    assertNotThrown(nxccfg.saveConfig("tests/default-unitest-expected.json"));
    assertNotThrown(nxccfg.loadConfig("tests/default-unitest-expected.json"));

    assertThrown(nxccfg.loadConfig("tests/defaultXX.json"));

    auto jsontext = nxccfg.jsonValues.toPrettyString;
    write("tests/default-new.json", jsontext);
    assert(jsontext == defJson);

    assert(nxccfg.serverUrl == "https://nexus.example.com");
    assert(nxccfg.repositories.length > 0);
    assert(nxccfg.repositories[0].nxRepository == "NexusTest");
    assert(nxccfg.repositories[0].minFiles == 5);
    assert(nxccfg.repositories[0].minAge == "90d");
    assert(nxccfg.repositories[0].nxRules.length == 2);
    assert(nxccfg.repositories[0].nxRules[0].group == "/Test-Autogen");
    assert(nxccfg.repositories[0].nxRules[0].minFiles == 5);
    assert(nxccfg.repositories[0].nxRules[0].minAge == "5min");
    assert(nxccfg.repositories[0].nxRules[0].groupFilesBy == "_");
    assert(nxccfg.repositories[0].nxRules[1].group == "/Test");
    assert(nxccfg.repositories[0].nxRules[1].minFiles == 5);
    assert(nxccfg.repositories[0].nxRules[1].minAge == "90d");
    assert(nxccfg.volumes[0].blobstore == "default");
    assert(nxccfg.volumes[0].minFreeSize == 4096);
    assert(nxccfg.volumes[1].mountpoint == "/usr");
    assert(nxccfg.volumes[1].minFreeSize == 8192);
}
