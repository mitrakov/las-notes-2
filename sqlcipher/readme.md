## Links
https://github.com/sqlcipher/sqlcipher
https://github.com/daybson/sqlite_cipher_windows/tree/master

## Build
```sh
git clone https://github.com/sqlcipher/sqlcipher.git
```

Makefile.msc:
```c
TCC = $(TCC) -DSQLITE_HAS_CODEC -DSQLITE_TEMP_STORE=2 -DSQLITE_EXTRA_INIT=sqlcipher_extra_init -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown -DSQLITE_THREADSAFE=1 -I"C:\Program Files\OpenSSL-Win64\include"

LTLIBPATHS = $(LTLIBPATHS) /LIBPATH:"C:\Program Files\OpenSSL-Win64\lib\VC\x64\MT"
LTLIBS = $(LTLIBS) libcrypto_static.lib libssl_static.lib ws2_32.lib shell32.lib advapi32.lib gdi32.lib user32.lib crypt32.lib
```

- Open "x64 Native Tools Command Pro" (from Visual Studio MSVC++), cd to sqlcipher project root dir and run:
```sh
nmake /f Makefile.msc
```
