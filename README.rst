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

There also exist dirb_ but it doesn't allow the user to specify the number of
threads which means a massive slowdown on my machine which wasn't acceptable
anymore.

Documentation
=============

::

    Fast brute force of web directories

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

TODO
====

- Specify your own list of invalid HTTP codes
- Add custom HEADER headers
- Allow the use of proxies
- Allow using other methods

Building
========

Simply do:

::

    dub build -b plain

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
