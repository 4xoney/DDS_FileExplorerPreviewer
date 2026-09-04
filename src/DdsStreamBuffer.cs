using System;
using System.IO;

namespace DdsThumbnailProvider
{
    internal static class DdsStreamBuffer
    {
        private const int CopyBufferSize = 64 * 1024;
        private const long MaximumInputLength = 256L * 1024L * 1024L;

        internal static MemoryStream CreateDecoderStream(Stream source)
        {
            if (source == null || !source.CanRead)
            {
                throw new InvalidDataException("The DDS input stream is not readable.");
            }

            if (source.CanSeek)
            {
                if (source.Length > MaximumInputLength)
                {
                    throw new InvalidDataException("The DDS file exceeds the safe encoded-size limit.");
                }

                source.Position = 0;
            }

            int initialCapacity = source.CanSeek ? checked((int)source.Length) : 0;
            var destination = new MemoryStream(initialCapacity);
            var buffer = new byte[CopyBufferSize];
            long totalBytes = 0;

            try
            {
                while (true)
                {
                    // Keep offset zero: SharpShell.Helpers.ComStream does not implement
                    // non-zero offsets, while an ordinary MemoryStream does.
                    int bytesRead = source.Read(buffer, 0, buffer.Length);
                    if (bytesRead == 0)
                    {
                        break;
                    }

                    totalBytes += bytesRead;
                    if (totalBytes > MaximumInputLength)
                    {
                        throw new InvalidDataException("The DDS file exceeds the safe encoded-size limit.");
                    }

                    destination.Write(buffer, 0, bytesRead);
                }

                destination.Position = 0;
                return destination;
            }
            catch
            {
                destination.Dispose();
                throw;
            }
        }
    }
}
