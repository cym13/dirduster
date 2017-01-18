
import std.stdio;
import std.array;
import std.algorithm;
import std.parallelism;

import requests;
import requests.http: Cookie;

immutable helpMsg =
"Fast brute force of web directories

Usage: dirduster [options] -f FILE URL...

Arguments:
    URL     Urls to bruteforce

Options:
    -h, --help             Print this help and exit
    -v, --version          Print the version and exit
    -a, --auth CREDS       Basic authentication in the format login:password
    -d, --directories      Identify and search directories
    -n, --num NUM          Number of threads to use, default is 10
    -c, --cookies COOKIES  User-defined cookies in the format a1=v1,a2=v2
    -f, --file FILE        Entries file
";


immutable invalidCodes = [0, 400, 403, 404, 405, 502];

void setCookie(Request rq, string url, string attr, string val) {
    string domain = url.split("/")[2];
    string path   = "/" ~ url.split("/")[3..$].join("/");
    rq.cookie(rq.cookie ~ Cookie(domain, path, attr, val));
}

string testEntry(
            Request rq,
            string baseUrl,
            string entry,
            bool checkDirs,
            string[string] cookies) {

    string url = baseUrl ~ entry;

    auto r = rq.get(url);
    cookies.each!((k,v) => rq.setCookie(url, k, v));

    if (invalidCodes.canFind(r.code))
        return null;

    immutable fullUri = r.uri.uri;

    writefln("%s\tCODE:%d SIZE:%d", fullUri, r.code, r.responseBody.length);

    if (!checkDirs)
        return null;

    if (fullUri.endsWith("/"))
        return fullUri;

    // TODO move this up, we shouldn't add entries here
    immutable fullDirUri = fullUri ~ "/";

    r = rq.get(fullDirUri);
    cookies.each!((k,v) => rq.setCookie(fullDirUri, k, v));

    if (!invalidCodes.canFind(r.code))
        return fullDirUri;

    return null;
}

string[] scanUrl(
            string baseUrl,
            const(string)[] entries,
            Request[] requestPool,
            bool checkDirs,
            string[string] cookies) {

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

        foreach (entry ; entries[firstEntry .. lastEntry]) {
            string url = testEntry(rq, baseUrl, entry, checkDirs, cookies);
            if (url)
                newUrlsPool[i] ~= url;
        }
    }

    return join(newUrlsPool);
}

auto loadEntries(string entryFile) {
    import std.file;
    import std.string: splitLines;

    if (entryFile == "-")
        return stdin.byLineCopy(KeepTerminator.no).array;
    return entryFile.readText.splitLines(KeepTerminator.no).array;
}

int main(string[] args) {
    import docopt;
    import std.conv;

    auto arguments = docopt.docopt(helpMsg, args[1..$], true, "0.3.0");

    auto baseUrls   = arguments["URL"].asList;
    auto entryFile  = arguments["--file"].toString;
    auto checkDirs  = !arguments["--directories"].isNull;
    auto numThreads = arguments["--num"].isNull
                        ? 10
                        : arguments["--num"].toString.to!uint;
    auto cookieStr  = arguments["--cookies"].isNull
                        ? []
                        : arguments["--cookies"].toString.split(",");
    auto basicAuth  = arguments["--auth"].isNull
                        ? ""
                        : arguments["--auth"].toString;

    defaultPoolThreads(numThreads);

    if (!entryFile.length)
        return 1;

    auto entries = loadEntries(entryFile);

    string[string] cookies;

    foreach (cookie ; cookieStr) {
        auto splitHere = cookie.countUntil("=");
        string attr = cookie[0..splitHere];
        string val  = cookie[splitHere+1..$];
        cookies[attr] = val;
    }

    Request[] requestPool;
    requestPool.length = numThreads;

    // Fill the request pool
    foreach (ref rq ; requestPool)
        rq.sslSetVerifyPeer(false);

    if (basicAuth != "") {
        auto splitHere  = basicAuth.countUntil(":");
        string login    = basicAuth[0..splitHere];
        string password = basicAuth[splitHere+1..$];


        foreach (ref rq ; requestPool)
            rq.authenticator = new BasicAuthentication(login, password);
    }

    if (baseUrls.any!((string x) => !x.startsWith("http")))
        writeln("WARNING: make sure you specified the right protocol");

    bool[string] oldUrls;
    while (baseUrls.length) {
        baseUrls = sort(baseUrls).uniq.array;

        string[] newUrls;
        foreach (baseUrl ; baseUrls) {
            if (!baseUrl.endsWith("/"))
                baseUrl ~= "/";

            writeln("\n-- Scanning ", baseUrl, " --\n");
            newUrls = scanUrl(baseUrl, entries, requestPool, checkDirs, cookies);
        }

        baseUrls = newUrls.filter!(url => url !in oldUrls).array;
        baseUrls.each!(url => oldUrls[url] = true);
    }

    return 0;
}
