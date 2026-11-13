#pragma once
#include <stddef.h>
#include <stdint.h>

class TH08IOSFileHandle
{
  public:
    TH08IOSFileHandle();
    ~TH08IOSFileHandle();
    bool Open(const char *path, char mode);
    void Close();
    size_t Read(void *destination, size_t length);
    bool Write(const void *source, size_t length);
    uint32_t Tell() const;
    uint32_t GetSize() const;
    bool Seek(uint32_t offset, int origin);
  private:
    int descriptor_;
};
