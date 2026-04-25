/*
   +----------------------------------------------------------------------+
   | Copyright (c) The PHP Group                                          |
   +----------------------------------------------------------------------+
   | This source file is subject to version 3.01 of the PHP license,      |
   | that is bundled with this package in the file LICENSE, and is        |
   | available through the world-wide-web at the following url:           |
   | https://www.php.net/license/3_01.txt                                 |
   | If you did not receive a copy of the PHP license and are unable to   |
   | obtain it through the world-wide-web, please send a note to          |
   | license@php.net so we can mail you a copy immediately.               |
   +----------------------------------------------------------------------+
   | Author: Stig Sæther Bakken <ssb@php.net>                             |
   +----------------------------------------------------------------------+
*/

#define CONFIGURE_COMMAND " '../php-8.3.30/configure'  '--host=arm-apple-darwin' '--with-pic' '--enable-zts' '--disable-cli' '--disable-cgi' '--disable-phar' '--disable-phpdbg' '--enable-embed=static' '--enable-mbstring' '--with-openssl' '--with-libxml' '--enable-dom' '--enable-simplexml' '--enable-xml' '--enable-xmlreader' '--enable-xmlwriter' '--enable-mysqlnd' '--disable-mysqlnd-compression-support' '--with-pdo-mysql=mysqlnd' '--with-mysqli=mysqlnd' '--without-sqlite3' '--without-pdo-sqlite' '--without-iconv' '--disable-opcache' 'host_alias=arm-apple-darwin' 'PKG_CONFIG_PATH=/Users/noguchi/Desktop/nativephp-mobile-mysql-template/mobile-libphp-builder/ios-build/ios-install/lib/pkgconfig' 'LIBXML_CFLAGS=-I/Users/noguchi/Desktop/nativephp-mobile-mysql-template/mobile-libphp-builder/ios-build/ios-install/include/libxml2' 'LIBXML_LIBS=-L/Users/noguchi/Desktop/nativephp-mobile-mysql-template/mobile-libphp-builder/ios-build/ios-install/lib -lxml2' 'OPENSSL_CFLAGS=-I/Users/noguchi/Desktop/nativephp-mobile-mysql-template/mobile-libphp-builder/ios-build/ios-install/include' 'OPENSSL_LIBS=-L/Users/noguchi/Desktop/nativephp-mobile-mysql-template/mobile-libphp-builder/ios-build/ios-install/lib -lssl -lcrypto' 'ONIG_CFLAGS=-I/Users/noguchi/Desktop/nativephp-mobile-mysql-template/mobile-libphp-builder/ios-build/ios-install/include' 'ONIG_LIBS=-L/Users/noguchi/Desktop/nativephp-mobile-mysql-template/mobile-libphp-builder/ios-build/ios-install/lib -lonig'"
#define PHP_ODBC_CFLAGS	""
#define PHP_ODBC_LFLAGS		""
#define PHP_ODBC_LIBS		""
#define PHP_ODBC_TYPE		""
#define PHP_OCI8_DIR			""
#define PHP_OCI8_ORACLE_VERSION		""
#define PHP_PROG_SENDMAIL	"/usr/sbin/sendmail"
#define PEAR_INSTALLDIR         ""
#define PHP_INCLUDE_PATH	".:"
#define PHP_EXTENSION_DIR       "/usr/local/lib/php/extensions/no-debug-zts-20230831"
#define PHP_PREFIX              "/usr/local"
#define PHP_BINDIR              "/usr/local/bin"
#define PHP_SBINDIR             "/usr/local/sbin"
#define PHP_MANDIR              "/usr/local/php/man"
#define PHP_LIBDIR              "/usr/local/lib/php"
#define PHP_DATADIR             "/usr/local/share/php"
#define PHP_SYSCONFDIR          "/usr/local/etc"
#define PHP_LOCALSTATEDIR       "/usr/local/var"
#define PHP_CONFIG_FILE_PATH    "/usr/local/lib"
#define PHP_CONFIG_FILE_SCAN_DIR    ""
#define PHP_SHLIB_SUFFIX        "so"
#define PHP_SHLIB_EXT_PREFIX    ""
