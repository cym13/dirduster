
import std.stdio;
import std.array;
import std.algorithm;
import std.parallelism;

import requests;

immutable helpMsg =
"Fast brute force of web directories

Usage: dirduster [-h] [-n NUM] -f FILE URL...

Arguments:
    URL     Urls to bruteforce

Options:
    -h, --help       Print this help and exit
    -v, --version    Print the version and exit
    -n, --num NUM    Number of threads to use, default is 10
    -f, --file FILE  Entries file
";


immutable invalidCodes = [0, 400, 403, 404, 405, 502];

// TODO Implement recursion
string[] scanUrl(
        string baseUrl,
        immutable(string)[] entries,
        Request[] requestPool) {

    try {
        URI(baseUrl);
    } catch (UriException) {
        return [];
    }

    immutable numThreads = requestPool.length;

    string[][] newUrlsPool;
    newUrlsPool.length = numThreads;

    foreach (i, ref rq ; taskPool.parallel(requestPool, 1)) {
        immutable firstEntry = i * entries.length / numThreads;
        immutable lastEntry  = min((i+1) * entries.length / numThreads,
                                   entries.length);

        if (firstEntry > lastEntry)
            continue;

        immutable(string)[] localEntries = entries[firstEntry .. lastEntry];

        foreach (entry ; localEntries) {
            stdout.flush;
            auto r = rq.get(baseUrl ~ entry);

            if (invalidCodes.canFind(r.code))
                continue;

            immutable fullUri = r.uri.uri;

            writefln("%s\t(CODE:%d:SIZE:%d)",
                     fullUri, r.code, r.responseBody.length);

            if (fullUri.endsWith("/"))
                newUrlsPool[i] ~= fullUri;
        }
    }

    return join(newUrlsPool);
}

int main(string[] args) {
    import docopt;
    import std.conv;
    import std.file;
    import std.string: splitLines;

    auto arguments = docopt.docopt(helpMsg, args[1..$], true, "0.1.0");

    auto baseUrls   = arguments["URL"].asList;
    auto entryFile  = arguments["--file"].toString;

    auto numThreads = arguments["--num"].isNull ?
                        10 : arguments["--num"].toString.to!uint;

    defaultPoolThreads(numThreads);

    if (!entryFile.length) {
        return 1;
    }

    immutable string[] entries = entryFile
                                    .readText
                                    .splitLines(KeepTerminator.no)
                                    .array;

    Request[] requestPool;
    requestPool.length = numThreads;

    foreach (ref rq ; requestPool) {
        rq.sslSetVerifyPeer(false);
    }

    foreach (baseUrl ; baseUrls) {
        if (!baseUrl.endsWith("/"))
            baseUrl ~= "/";

        writeln("\n-- Scanning ", baseUrl, " --\n");
        scanUrl(baseUrl, entries, requestPool);
    }

    return 0;
}
