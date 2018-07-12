Description
===========

DirDuster is a web directory bruteforcing tool similar to DirBuster.
It allows you to quickly check for the presence of files or directories in
order to detect potential flaws in the way the web server is configured.

Why DirDuster?
==============

The main tool used for this task is DirBuster_ which is written in Java and
uses a graphical interface. This makes it hard enough to use for me to prefer
writting another tool with a more proper interface.

.. _DirBuster: https://www.owasp.org/index.php/Category:OWASP_DirBuster_Project

There also exist dirb_ but it doesn't allow the user to specify the number of
threads which means a massive slowdown on my machine which wasn't acceptable
anymore.

.. _dirb: http://dirb.sourceforge.net/

How can I change the user-agent or use basic authentication?
============================================================

Setup custom headers using the --header option:

::

    dirduster -H "User-Agent=Whatever,Basic=YTphCg==" -f pathlist.txt test.com

For basic authentication you can also use the --auth option.


Documentation
=============

::

    Usage: dirduster [options] -f FILE URL...

    Arguments:
        URL     Urls to bruteforce

    Options:
        -h, --help             Print this help and exit
        -v, --version          Print the version and exit

        -a, --auth CREDS       Basic authentication in the format login:password
        -c, --cookies COOKIES  User-defined cookies in the format a1=v1,a2=v2
        -d, --directories      Identify and search directories
        -f, --file FILE        Entries file
        -H, --headers HEADERS  User-defined headers in the format header=value
                               Use multiple times for multiple headers
        -i, --ignore CODES     List of comma separated invalid codes
        -I, --list-ignore      List the default invalid codes
        -p, --proxy PROXY_URL  Proxy url; may contain authentication data
        -s, --single-pass      Disable recursion on findings
        -t, --threads NUM      Number of threads to use, default is 10
        -u, --user-agent UA    Set custom user agent
        -x, --exclude REGEX    Exclude pages matching REGEX

TODO
====

- Allow using other methods -> unlikely to be soon as dlang-requests doesn't
  support any besides GET and POST.

Building
========

Use dub with the **safe-prod** build that optimizes the code without
disabling safety features.

::

    dub build -b safe-prod

License
=======

This program is under the GPLv3 License.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.

Contact
=======

::

    Main developper: Cédric Picard
    Email:           cedric.picard@efrei.net
