
import std.stdio;
import std.array;
import std.algorithm;
import std.parallelism;

import requests;
import requests.http: Cookie;

/**
 * Help message, standard unix format compatible with docopt.
 */
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


/**
 * Default codes to ignore in answer to requests
 */
immutable invalidCodes = [0, 400, 403, 404, 405, 502];


/**
 * Helper: add a cookie to a request
 */
void setCookie(Request rq, string url, string attr, string val) {
    string domain = url.split("/")[2];
    string path   = "/" ~ url.split("/")[3..$].join("/");
    rq.cookie(rq.cookie ~ Cookie(domain, path, attr, val));
}

/**
 * Scan a given url given a list of entries
 */
string[] scanUrl(
            string baseUrl,
            const(string)[] entries,
            Request[] requestPool,
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
            cookies.each!((k,v) => rq.setCookie(baseUrl ~ entry, k, v));

            string url = baseUrl ~ entry;
            auto   r   = rq.get(url);

            if (invalidCodes.canFind(r.code))
                continue;

            writefln("%s\tCODE:%d SIZE:%d",
                     r.uri.uri, r.code, r.responseBody.length);
            newUrlsPool[i] ~= r.uri.uri;
        }
    }

    return join(newUrlsPool);
}

/**
 * Load entries from a given file
 */
auto loadEntries(string entryFile, bool checkDirs) {
    import std.file:   readText;
    import std.string: splitLines;

    string[] results;

    if (entryFile == "-")
        results = stdin.byLineCopy(KeepTerminator.no).array;
    results = entryFile.readText.splitLines(KeepTerminator.no).array;

    if (checkDirs) {
        results ~= results.filter!(u => !u.endsWith("/") && u.length > 0)
                          .map!(u => u ~ "/")
                          .array;
    }

    return results;
}


int main(string[] args) {
    import docopt: docopt;
    import std.conv: to;

    // I love docopt but this implementation sucks
    auto arguments = docopt(helpMsg, args[1..$], true, "0.5.0");

    auto baseUrls   = arguments["URL"].asList;
    auto entryFile  = arguments["--file"].toString;
    auto checkDirs  = arguments["--directories"].toString == "true";
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

    auto entries = loadEntries(entryFile, checkDirs);

    string[string] cookies;
    foreach (cookie ; cookieStr) {
        immutable sep  = cookie.countUntil("=");
        immutable attr = cookie[0..sep];
        immutable val  = cookie[sep+1..$];

        cookies[attr] = val;
    }

    Auth authenticator;
    if (basicAuth != "") {
        immutable sep      = basicAuth.countUntil(":");
        immutable login    = basicAuth[0..sep];
        immutable password = basicAuth[sep+1..$];

        authenticator = new BasicAuthentication(login, password);
    }

    Request[] requestPool;
    requestPool.length = numThreads;

    // Fill the request pool
    foreach (ref rq ; requestPool) {
        rq.sslSetVerifyPeer(false);
        rq.authenticator = authenticator;
    }

    if (baseUrls.any!((string x) => !x.startsWith("http")))
        writeln("WARNING: make sure you specified the right protocol");

    bool[string] oldUrls;
    while (baseUrls.length) {
        baseUrls = sort(baseUrls).uniq.array;
        baseUrls.each!(url => oldUrls[url] = true);

        string[] newUrls;
        foreach (baseUrl ; baseUrls) {
            if (!baseUrl.endsWith("/"))
                baseUrl ~= "/";

            writeln("\n-- Scanning ", baseUrl, " --\n");
            newUrls = scanUrl(baseUrl, entries, requestPool, cookies);
        }

        baseUrls = newUrls.filter!(url => url !in oldUrls).array;
    }

    return 0;
}
