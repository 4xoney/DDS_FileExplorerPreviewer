using System;
using System.IO;

namespace DdsThumbnailProvider
{
    internal static class DdsHeaderValidator
    {
        private const int RequiredHeaderBytes = 20;
        private const uint DdsHeaderSize = 124;
        private const int MaximumDimension = 32768;
        private const long MaximumPixelCount = 64L * 1024L * 1024L;

        internal static bool TryValidate(Stream stream, out string error)
        {
            error = null;

            if (stream == null || !stream.CanRead)
            {
                error = "the input stream is not readable";
                return false;
            }

            if (!stream.CanSeek)
            {
                error = "the input stream is not seekable";
                return false;
            }

            long originalPosition = stream.Position;
            var header = new byte[RequiredHeaderBytes];

            try
            {
                stream.Position = 0;
                int read = 0;
                while (read < header.Length)
                {
                    int count = stream.Read(header, read, header.Length - read);
                    if (count == 0)
                    {
                        error = "the file is shorter than a DDS header";
                        return false;
                    }

                    read += count;
                }

                if (header[0] != (byte)'D' || header[1] != (byte)'D' ||
                    header[2] != (byte)'S' || header[3] != (byte)' ')
                {
                    error = "the DDS magic value is missing";
                    return false;
                }

                if (ReadUInt32(header, 4) != DdsHeaderSize)
                {
                    error = "the DDS header size is invalid";
                    return false;
                }

                uint height = ReadUInt32(header, 12);
                uint width = ReadUInt32(header, 16);
                if (width == 0 || height == 0 || width > MaximumDimension || height > MaximumDimension)
                {
                    error = "the DDS dimensions are invalid or too large";
                    return false;
                }

                if ((long)width * height > MaximumPixelCount)
                {
                    error = "the DDS exceeds the safe decoded pixel limit";
                    return false;
                }

                return true;
            }
            finally
            {
                stream.Position = originalPosition;
            }
        }

        private static uint ReadUInt32(byte[] bytes, int offset)
        {
            return (uint)(bytes[offset]
                | (bytes[offset + 1] << 8)
                | (bytes[offset + 2] << 16)
                | (bytes[offset + 3] << 24));
        }
    }
}
