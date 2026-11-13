#include "th_pch.h"

#include "pbg/PbgFile.hpp"

#ifdef TH08_MODERN_IOS
#include <stdio.h>
#endif

namespace th08
{
DIFFABLE_STATIC_ARRAY_ASSIGN(i32, 3, g_PbgFileSeekModes) = {FILE_BEGIN, FILE_CURRENT, FILE_END};
DIFFABLE_STATIC_ARRAY_ASSIGN(char *, 3, g_PbgFileOpenModes) = {"r", "w", "a"};

CPbgFile::CPbgFile()
{
#ifndef TH08_MODERN_IOS
    m_hFile = INVALID_HANDLE_VALUE;
#endif
    m_DesiredAccess = 0;
}

CPbgFile::~CPbgFile()
{
    Close();
}

#pragma var_order(curMode, goToEnd, filePathBuffer, creationDisposition)
bool CPbgFile::Open(const char *filename, char *mode)
{
#ifndef TH08_MODERN_IOS
    DWORD creationDisposition;
    BOOL goToEnd = FALSE;
    char filePathBuffer[MAX_PATH];
#endif
    if (filename == NULL || mode == NULL)
        return false;

    Close();

    char *curMode;
    for (curMode = mode; *curMode != '\0'; curMode++)
    {
        if (*curMode == 'r')
        {
            m_DesiredAccess = GENERIC_READ;
#ifndef TH08_MODERN_IOS
            creationDisposition = OPEN_EXISTING;
#endif
            break;
        }
        if (*curMode == 'w')
        {
#ifndef TH08_MODERN_IOS
            DeleteFileA(filename);
            creationDisposition = CREATE_ALWAYS;
#endif
            m_DesiredAccess = GENERIC_WRITE;
            break;
        }
        if (*curMode == 'a')
        {
#ifndef TH08_MODERN_IOS
            goToEnd = TRUE;
            creationDisposition = OPEN_ALWAYS;
#endif
            m_DesiredAccess = GENERIC_WRITE;
            break;
        }
    }

    if (*curMode == '\0')
    {
        m_DesiredAccess = 0;
        return false;
    }

#ifdef TH08_MODERN_IOS
    if (!m_file.Open(filename, *curMode))
    {
        m_DesiredAccess = 0;
        return false;
    }
    return true;
#else
#ifdef TH08_MODERN_PORT
    WCHAR wideFilename[MAX_PATH];
    if (MultiByteToWideChar(CP_ACP, 0, filename, -1, wideFilename, MAX_PATH) == 0)
        return false;
    m_hFile = CreateFileW(wideFilename, m_DesiredAccess, FILE_SHARE_READ, NULL, creationDisposition,
                          FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, NULL);
#else
    GetFullFilePath(filePathBuffer, filename);
    m_hFile = CreateFileA(filePathBuffer, m_DesiredAccess, FILE_SHARE_READ, NULL, creationDisposition,
                          FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, NULL);
#endif
    if (m_hFile == INVALID_HANDLE_VALUE)
    {
        m_DesiredAccess = 0;
        return false;
    }
    if (goToEnd)
        SetFilePointer(m_hFile, 0, NULL, FILE_END);
    return true;
#endif
}

void CPbgFile::Close()
{
#ifdef TH08_MODERN_IOS
    m_file.Close();
#else
    if (m_hFile != INVALID_HANDLE_VALUE)
    {
        CloseHandle(m_hFile);
        m_hFile = INVALID_HANDLE_VALUE;
    }
#endif
    m_DesiredAccess = 0;
}

DWORD CPbgFile::Read(LPVOID data, DWORD dataLen)
{
    if (m_DesiredAccess != GENERIC_READ)
        return 0;
#ifdef TH08_MODERN_IOS
    return static_cast<DWORD>(m_file.Read(data, dataLen));
#else
    DWORD numBytesRead = 0;
    ReadFile(m_hFile, data, dataLen, &numBytesRead, NULL);
    return numBytesRead;
#endif
}
bool CPbgFile::Write(LPVOID data, DWORD dataLen)
{
    if (m_DesiredAccess != GENERIC_WRITE)
        return false;
#ifdef TH08_MODERN_IOS
    return m_file.Write(data, dataLen);
#else
    DWORD outWritten = 0;
    WriteFile(m_hFile, data, dataLen, &outWritten, NULL);
    return dataLen == outWritten;
#endif
}
DWORD CPbgFile::Tell()
{
#ifdef TH08_MODERN_IOS
    return m_file.Tell();
#else
    if (m_hFile == INVALID_HANDLE_VALUE)
        return 0;
    return SetFilePointer(m_hFile, 0, NULL, FILE_CURRENT);
#endif
}
DWORD CPbgFile::GetSize()
{
#ifdef TH08_MODERN_IOS
    return m_file.GetSize();
#else
    if (m_hFile == INVALID_HANDLE_VALUE)
        return 0;
    return GetFileSize(m_hFile, NULL);
#endif
}
bool CPbgFile::Seek(DWORD offset, DWORD seekFrom)
{
#ifdef TH08_MODERN_IOS
    return m_file.Seek(offset, static_cast<int>(seekFrom));
#else
    if (m_hFile == INVALID_HANDLE_VALUE)
        return false;
    SetFilePointer(m_hFile, offset, NULL, seekFrom);
    return true;
#endif
}
HGLOBAL CPbgFile::ReadWholeFile(DWORD maxSize)
{
    if (m_DesiredAccess != GENERIC_READ)
    {
        return NULL;
    }

    DWORD dataLen = GetSize();
    if (dataLen > maxSize)
    {
        return NULL;
    }

    HGLOBAL data = GlobalAlloc(LPTR, dataLen);
    if (data == NULL)
    {
        return NULL;
    }

    DWORD oldLocation = Tell();
    if (Seek(oldLocation, g_PbgFileSeekModes[0]) == 0)
    {
        return NULL;
    }

    if (Read(data, dataLen) == 0)
    {
        if (data)
        {
            GlobalFree(data);
            data = NULL;
        }
        return NULL;
    }

    Seek(oldLocation, g_PbgFileSeekModes[0]);
    return data;
}

void CPbgFile::GetFullFilePath(char *buffer, const char *filename)
{
#ifdef TH08_MODERN_IOS
    if (buffer == NULL || filename == NULL)
        return;
    snprintf(buffer, MAX_PATH, "%s", filename);
#else
    if (strchr(filename, ':') != NULL)
    {
        strcpy(buffer, filename);
    }
    else
    {
        GetModuleFileNameA(NULL, buffer, MAX_PATH);
        char *endOfModulePath = strrchr(buffer, '\\');
        if (endOfModulePath == NULL)
        {
            strcpy(buffer, "");
        }
        endOfModulePath[1] = '\0';
        strcat(buffer, filename);
    }
#endif
}
// FUNCTION: th08 0x473c40
IPbgFile::IPbgFile()
{
}

// FUNCTION: th08 0x473c60
IPbgFile::~IPbgFile()
{
}

}; // namespace th08
