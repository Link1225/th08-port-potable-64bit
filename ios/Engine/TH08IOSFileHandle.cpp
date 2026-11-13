#include "TH08IOSFileHandle.hpp"
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

TH08IOSFileHandle::TH08IOSFileHandle() : descriptor_(-1) {}
TH08IOSFileHandle::~TH08IOSFileHandle() { Close(); }

bool TH08IOSFileHandle::Open(const char *path, char mode)
{
    if (path == NULL || path[0] == '\0')
        return false;
    Close();
    int flags = 0;
    switch (mode)
    {
    case 'r': flags = O_RDONLY; break;
    case 'w': flags = O_WRONLY | O_CREAT | O_TRUNC; break;
    case 'a': flags = O_WRONLY | O_CREAT | O_APPEND; break;
    default: return false;
    }
#ifdef O_CLOEXEC
    flags |= O_CLOEXEC;
#endif
    descriptor_ = open(path, flags, 0666);
    if (descriptor_ < 0)
        return false;
    if (mode == 'a' && lseek(descriptor_, 0, SEEK_END) < 0)
    {
        Close();
        return false;
    }
    return true;
}

void TH08IOSFileHandle::Close()
{
    if (descriptor_ >= 0)
    {
        close(descriptor_);
        descriptor_ = -1;
    }
}

size_t TH08IOSFileHandle::Read(void *destination, size_t length)
{
    if (descriptor_ < 0 || destination == NULL || length == 0)
        return 0;
    size_t total = 0;
    unsigned char *cursor = static_cast<unsigned char *>(destination);
    while (total < length)
    {
        const ssize_t amount = read(descriptor_, cursor + total, length - total);
        if (amount < 0)
        {
            if (errno == EINTR) continue;
            break;
        }
        if (amount == 0) break;
        total += static_cast<size_t>(amount);
    }
    return total;
}

bool TH08IOSFileHandle::Write(const void *source, size_t length)
{
    if (descriptor_ < 0 || (source == NULL && length != 0))
        return false;
    size_t total = 0;
    const unsigned char *cursor = static_cast<const unsigned char *>(source);
    while (total < length)
    {
        const ssize_t amount = write(descriptor_, cursor + total, length - total);
        if (amount < 0)
        {
            if (errno == EINTR) continue;
            return false;
        }
        if (amount == 0) return false;
        total += static_cast<size_t>(amount);
    }
    return true;
}

uint32_t TH08IOSFileHandle::Tell() const
{
    if (descriptor_ < 0) return 0;
    const off_t offset = lseek(descriptor_, 0, SEEK_CUR);
    if (offset < 0 || static_cast<uint64_t>(offset) > UINT32_MAX) return 0;
    return static_cast<uint32_t>(offset);
}

uint32_t TH08IOSFileHandle::GetSize() const
{
    if (descriptor_ < 0) return 0;
    struct stat info;
    if (fstat(descriptor_, &info) != 0 || info.st_size < 0 ||
        static_cast<uint64_t>(info.st_size) > UINT32_MAX) return 0;
    return static_cast<uint32_t>(info.st_size);
}

bool TH08IOSFileHandle::Seek(uint32_t offset, int origin)
{
    if (descriptor_ < 0) return false;
    int whence;
    switch (origin)
    {
    case 0: whence = SEEK_SET; break;
    case 1: whence = SEEK_CUR; break;
    case 2: whence = SEEK_END; break;
    default: return false;
    }
    return lseek(descriptor_, static_cast<off_t>(offset), whence) >= 0;
}
