#include "TH08IOSFileHandle.hpp"
#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

int main()
{
    char path[] = "/tmp/th08-ios-file-handle-XXXXXX";
    const int seed = mkstemp(path);
    assert(seed >= 0);
    close(seed);
    unlink(path);

    const char original[] = "TH08 PBG archive reader";
    TH08IOSFileHandle file;
    assert(file.Open(path, 'w'));
    assert(file.Write(original, sizeof(original)));
    assert(file.Tell() == sizeof(original));
    assert(file.GetSize() == sizeof(original));
    assert(file.Seek(0, 0));

    char buffer[sizeof(original)];
    memset(buffer, 0, sizeof(buffer));
    assert(file.Read(buffer, sizeof(buffer)) == sizeof(buffer));
    assert(memcmp(buffer, original, sizeof(original)) == 0);
    assert(file.Read(buffer, 1) == 0);
    file.Close();

    assert(file.Open(path, 'a'));
    assert(file.Tell() == sizeof(original));
    const char suffix[] = " + append";
    assert(file.Write(suffix, sizeof(suffix)));
    assert(file.GetSize() == sizeof(original) + sizeof(suffix));
    file.Close();

    assert(file.Open(path, 'r'));
    assert(file.GetSize() == sizeof(original) + sizeof(suffix));
    assert(file.Seek(sizeof(original), 0));
    memset(buffer, 0, sizeof(buffer));
    assert(file.Read(buffer, sizeof(suffix)) == sizeof(suffix));
    assert(memcmp(buffer, suffix, sizeof(suffix)) == 0);
    file.Close();

    assert(!file.Open("/tmp/th08-file-that-does-not-exist/never.dat", 'r'));
    unlink(path);
    return 0;
}
