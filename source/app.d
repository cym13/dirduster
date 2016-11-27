
import std.stdio;
import std.array;
import std.algorithm;
import std.parallelism;

import requests;

immutable helpMsg =
"Fast brute force of web directories

Usage: dirduster [options] -f FILE URL...

Arguments:
    URL     Urls to bruteforce

Options:
    -h, --help         Print this help and exit
    -v, --version      Print the version and exit
    -d, --directories  Identify and search directories
    -n, --num NUM      Number of threads to use, default is 10
    -f, --file FILE    Entries file
";


immutable invalidCodes = [0, 400, 403, 404, 405, 502];

string testEntry(Request rq, string baseUrl, string entry, bool checkDirs) {
    string url = baseUrl ~ entry;

    auto r = rq.get(url);

    if (invalidCodes.canFind(r.code))
        return null;

    immutable fullUri = r.uri.uri;

    writefln("%s\tCODE:%d SIZE:%d", fullUri, r.code, r.responseBody.length);

    if (!checkDirs)
        return null;

    if (fullUri.endsWith("/"))
        return fullUri;

    r = rq.get(fullUri ~ "/");
    if (!invalidCodes.canFind(r.code))
        return fullUri;

    return null;
}

string[] scanUrl(
            string baseUrl,
            immutable(string)[] entries,
            Request[] requestPool,
            bool checkDirs) {

    try
        URI(baseUrl);
    catch (UriException)
        return [];

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
            string url = testEntry(rq, baseUrl, entry, checkDirs);
            if (url)
                newUrlsPool[i] ~= url;
        }
    }

    return join(newUrlsPool);
}

int main(string[] args) {
    import docopt;
    import std.conv;
    import std.file;
    import std.string: splitLines;

    auto arguments = docopt.docopt(helpMsg, args[1..$], true, "0.2.0");

    auto baseUrls   = arguments["URL"].asList;
    auto entryFile  = arguments["--file"].toString;
    auto numThreads = arguments["--num"].isNull ?
                        10 : arguments["--num"].toString.to!uint;
    auto checkDirs  = !arguments["--directories"].isNull;

    defaultPoolThreads(numThreads);

    if (!entryFile.length)
        return 1;

    immutable string[] entries = entryFile
                                    .readText
                                    .splitLines(KeepTerminator.no)
                                    .array;

    Request[] requestPool;
    requestPool.length = numThreads;

    foreach (ref rq ; requestPool)
        rq.sslSetVerifyPeer(false);

    while (baseUrls.length) {
        bool[string] oldUrls;

        baseUrls = sort(baseUrls).uniq.array;

        string[] newUrls;
        foreach (baseUrl ; baseUrls) {
            if (!baseUrl.endsWith("/"))
                baseUrl ~= "/";

            writeln("\n-- Scanning ", baseUrl, " --\n");
            newUrls = scanUrl(baseUrl, entries, requestPool, checkDirs);
        }

        baseUrls = newUrls.filter!(url => url !in oldUrls).array;
        baseUrls.each!(url => oldUrls[url] = true);
    }

    return 0;
}
