# Compiling libsqlite3.so with SQLCipher
The 2 files (`sqlite3` and `libsqlite3.so`) are already included. If you want to compile them yourself, follow this guide.
[Link](https://github.com/sqlcipher/sqlcipher)

## Build (example for Ubuntu/Debian with OpenSSL)
```sh
apt install clang cmake
apt install libssl-dev      # check /usr/include/openssl/
./configure --with-tempstore=yes --disable-math --enable-fts5 CFLAGS="-DSQLITE_HAS_CODEC -DSQLITE_EXTRA_INIT=sqlcipher_extra_init -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown -I/usr/include/openssl" LDFLAGS="-lcrypto"
make
```
