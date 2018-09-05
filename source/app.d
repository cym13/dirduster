
import std.array;
import std.algorithm;
import std.parallelism;
import std.regex;
import std.stdio;

import requests;


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
    -c, --cookies COOKIES  User-defined cookies in the format Cookie=Value
                           Use multiple times for multiple cookies
    -d, --directories      Identify and search directories
    -f, --file FILE        Entries file
    -H, --headers HEADERS  User-defined headers in the format Header=Value
                           Use multiple times for multiple headers
    -i, --ignore CODES     List of comma separated invalid codes
    -I, --list-ignore      List the default invalid codes
    -p, --proxy PROXY_URL  Proxy url; may contain authentication data
    -s, --single-pass      Disable recursion on findings
    -t, --threads NUM      Number of threads to use, default is 10
    -u, --user-agent UA    Set custom user agent
    -x, --exclude REGEX    Exclude pages matching REGEX
";

immutable vernum="1.4.1";

/**
 * Helper: add a cookie to a request
 */
void setCookie(ref HTTPRequest rq, string url, string attr, string val) {
    import requests.utils: Cookie;
    string domain = url.split("/")[2];
    string path   = "/" ~ url.split("/")[3..$].join("/");
    rq.cookie(rq.cookie ~ [Cookie(path, domain, attr, val)]);
}

/**
 * Scan a given url given a list of entries
 */
string[] scanUrl(
            string baseUrl,
            const(string)[] entries,
            HTTPRequest[] requestPool,
            ushort[] invalidCodes,
            string[string] cookies,
            Regex!char exclude) {

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

            HTTPResponse r;

            try {
                r = rq.get(url);
            } catch (TimeoutException) {
                stderr.writeln("Timeout: ", url);
                continue;
            } catch (RequestException e) {
                // This is hideous, but requests leaves me no choice
                if (e.msg.canFind("Unknown content-encoding")) {
                    stderr.writeln("Ignoring because encoding error: ", url);
                    continue;
                }
                else {
                    throw e;
                }
            } catch (Exception e) {
                // Ditto
                if (e.msg.canFind("ssl connect failed")) {
                    stderr.writeln("Ignoring because SSL error: ", url);
                    continue;
                }
                else {
                    throw e;
                }
            }

            if (invalidCodes.canFind(r.code))
                continue;

            if (!exclude.empty) {
                import std.string: assumeUTF;
                auto data = r.responseBody.data.assumeUTF;
                if (!matchFirst(data, exclude).empty)
                    continue;
            }

            writefln("%s\tCODE:%d SIZE:%d",
                     r.uri.uri, r.code, r.responseBody.length);
            stdout.flush;
            newUrlsPool[i] ~= r.uri.uri;
        }
    }

    return join(newUrlsPool);
}

/**
 * Load entries from a given file
 */
auto loadEntries(string entryFile, bool checkDirs) {
    import std.conv:   to;
    import std.file:   read;
    import std.string: splitLines;

    string[] results;

    if (entryFile == "-")
        results = stdin.byLineCopy(KeepTerminator.no).array;
    else
        results = entryFile.read.to!string.splitLines(KeepTerminator.no).array;

    if (checkDirs) {
        results ~= results.filter!(u => !u.endsWith("/") && u.length > 0)
                          .map!(u => u ~ "/")
                          .array;
    }

    return results;
}


int main(string[] args) {
    import std.getopt;
    import std.conv: to;

    ushort[] defaultInvalidCodes = [0, 400, 403, 404, 405, 502];

    /* Setup options */

    bool             checkDirs;
    bool             listInvalidCodes;
    bool             versionWanted;
    bool             singlePass;
    string           basicAuth;
    string           entryFile;
    string           proxy;
    string           exclude;
    string[string]   cookies;
    string[string]   headers;
    uint             numThreads = 10;
    ushort[]         invalidCodes;
    string           userAgent = "Mozilla/5.0 (Windows NT 6.1; WOW64; "
                               ~ "Trident/7.0; rv:11.0) like Gecko";

    try {
        auto arguments = getopt(args,
                                std.getopt.config.bundling,
                                std.getopt.config.caseSensitive,
                                "a|auth",        &basicAuth,
                                "c|cookies",     &cookies,
                                "d|directories", &checkDirs,
                                "f|file",        &entryFile,
                                "H|headers",     &headers,
                                "i|ignore",      &invalidCodes,
                                "I|list-ignore", &listInvalidCodes,
                                "p|proxy",       &proxy,
                                "s|singl-epass", &singlePass,
                                "t|threads",     &numThreads,
                                "u|user-agent",  &userAgent,
                                "x|exclude",     &exclude,
                                "v|version",     &versionWanted);

        if (arguments.helpWanted) {
            write(helpMsg);
            return 0;
        }
        if (versionWanted) {
            writeln(vernum);
            return 0;
        }
        if (listInvalidCodes) {
            defaultInvalidCodes.map!(to!string).join(",").writeln;
            return 0;
        }

    } catch (GetOptException ex) {
        stderr.write(helpMsg);
        return 1;
    }

    /* Load url list */

    string[] baseUrls = args[1..$];

    if (!entryFile.length || !baseUrls.length) {
        stderr.write(helpMsg);
        return 1;
    }

    auto entries = loadEntries(entryFile, checkDirs);

    /* Option check */

    if (!invalidCodes.length)
        invalidCodes = defaultInvalidCodes;

    Auth authenticator;
    if (basicAuth != "") {
        immutable sep      = basicAuth.countUntil(":");
        immutable login    = basicAuth[0..sep];
        immutable password = basicAuth[sep+1..$];

        authenticator = new BasicAuthentication(login, password);
    }

    if (baseUrls.any!((string x) => !x.startsWith("http")))
        writeln("WARNING: make sure you specified the right protocol");

    if ("User-Agent" !in headers)
        headers["User-Agent"] = userAgent;

    Regex!char regExclude;
    if (exclude)
        regExclude = regex(exclude);

    /* Setup the request pool */

    defaultPoolThreads(numThreads);
    HTTPRequest[] requestPool;
    requestPool.length = numThreads;

    foreach (ref rq ; requestPool) {
        rq.sslSetVerifyPeer(false);
        rq.authenticator = authenticator;
        rq.addHeaders(headers);
        rq.proxy = proxy;
    }

    /* Start scanning */

    bool[string] oldUrls;
    while (baseUrls.length) {
        baseUrls = sort(baseUrls).uniq.array;
        baseUrls.each!(url => oldUrls[url] = true);

        string[] newUrls;
        foreach (baseUrl ; baseUrls) {
            if (!baseUrl.endsWith("/"))
                baseUrl ~= "/";

            writeln("\n-- Scanning ", baseUrl, " --\n");
            newUrls = scanUrl(baseUrl, entries, requestPool,
                              invalidCodes, cookies, regExclude);
        }

        if (singlePass)
            break;

        baseUrls = newUrls.filter!(url => url !in oldUrls).array;
    }

    writeln("-- END --");

    return 0;
}
