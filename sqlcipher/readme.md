# Compiling sqlite3.dll with SQLCipher
The 2 files (sqlite3.dll and sqlite3.exe) are already included. If you want to compile them yourself, follow this guide.

## Links
https://github.com/sqlcipher/sqlcipher
https://github.com/daybson/sqlite_cipher_windows/tree/master

## Soft
1. Install ActiveTcl library v8.6, move it to "C:\Tcl" (check correct path in Makefile.msc), and add "C:\Tcl\bin" to your PATH.
2. Install full version of OpenSSL-Win64 library (https://slproweb.com/products/Win32OpenSSL.html), or use my copy from the ZIP archive

## Build
Clone repo:
```sh
git clone https://github.com/sqlcipher/sqlcipher.git
```

Update `Makefile.msc` (verify all your paths properly!):
```
# Find last occurrence of "TCC = $(TCC)" and add below:
TCC = $(TCC) -DSQLITE_HAS_CODEC -DSQLITE_TEMP_STORE=2 -DSQLITE_EXTRA_INIT=sqlcipher_extra_init -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown -DSQLITE_THREADSAFE=1 -I"C:\Program Files\OpenSSL-Win64\include"

# Find last occurrence of "LTLIBPATHS = $(LTLIBPATHS)" and add below:
LTLIBPATHS = $(LTLIBPATHS) /LIBPATH:"C:\Program Files\OpenSSL-Win64\lib\VC\x64\MT"
LTLIBS = $(LTLIBS) libcrypto_static.lib libssl_static.lib ws2_32.lib shell32.lib advapi32.lib gdi32.lib user32.lib crypt32.lib
```

Open "x64 Native Tools Command Prompt" (from Visual Studio MSVC 2022 installation), navigate to the `sqlcipher` project root and run:
```sh
nmake /f Makefile.msc
```

If you encounter an error "error C2061: syntax error: identifier 'xoshiro_s'", add the following line in `sqlite3.c` beforehand:
```c
#include <stdint.h>
```
