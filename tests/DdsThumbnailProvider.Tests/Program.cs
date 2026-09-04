using System;
using System.Drawing;
using System.IO;
using Pfim;
using SharpShell.Interop;
using ComTypes = System.Runtime.InteropServices.ComTypes;
using System.Runtime.InteropServices;

namespace DdsThumbnailProvider.Tests
{
    internal static class Program
    {
        private static int Main(string[] args)
        {
            try
            {
                HeaderValidationAcceptsDdsAndRestoresPosition();
                HeaderValidationRejectsOversizedImages();
                DecoderAndConverterPreservePixels();
                BlockCompressedDdsDecodes();
                MipmappedDdsDecodesThroughOffsetLimitedStream();
                MipmappedDdsDecodesThroughThumbnailComInterfaces();
                ThumbnailMaintainsAspectRatio();
                ThumbnailDoesNotUpscaleSmallImages();

                if (args.Length == 1)
                {
                    VerifyDirectoryThroughThumbnailComInterfaces(args[0]);
                }

                Console.WriteLine("All DDS thumbnail provider smoke tests passed.");
                return 0;
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine(exception);
                return 1;
            }
        }

        private static void HeaderValidationAcceptsDdsAndRestoresPosition()
        {
            using (var stream = new MemoryStream(CreateBgra32Dds(2, 1, new byte[8])))
            {
                stream.Position = 7;
                string error;
                Assert(DdsHeaderValidator.TryValidate(stream, out error), error);
                Assert(stream.Position == 7, "Header validation did not restore the stream position.");
            }
        }

        private static void HeaderValidationRejectsOversizedImages()
        {
            byte[] dds = CreateBgra32Dds(2, 1, new byte[8]);
            WriteUInt32(dds, 16, 32769);
            using (var stream = new MemoryStream(dds))
            {
                string error;
                Assert(!DdsHeaderValidator.TryValidate(stream, out error), "An oversized DDS was accepted.");
            }
        }

        private static void DecoderAndConverterPreservePixels()
        {
            byte[] pixels =
            {
                0, 0, 255, 255,
                0, 255, 0, 128
            };

            using (var stream = new MemoryStream(CreateBgra32Dds(2, 1, pixels)))
            using (IImage image = Pfimage.FromStream(stream))
            using (Bitmap bitmap = DdsBitmapConverter.CreateThumbnail(image, 2))
            {
                Assert(bitmap.Size == new Size(2, 1), "Unexpected decoded bitmap dimensions.");
                Assert(bitmap.GetPixel(0, 0).ToArgb() == Color.FromArgb(255, 255, 0, 0).ToArgb(), "Red pixel was not preserved.");
                Assert(bitmap.GetPixel(1, 0).ToArgb() == Color.FromArgb(128, 0, 255, 0).ToArgb(), "Green alpha pixel was not preserved.");
            }
        }

        private static void ThumbnailMaintainsAspectRatio()
        {
            Size size = DdsBitmapConverter.CalculateThumbnailSize(1024, 512, 256);
            Assert(size == new Size(256, 128), "Thumbnail aspect ratio was not preserved.");
        }

        private static void ThumbnailDoesNotUpscaleSmallImages()
        {
            Size size = DdsBitmapConverter.CalculateThumbnailSize(32, 16, 256);
            Assert(size == new Size(32, 16), "Small images should not be enlarged by the provider.");
        }

        private static void BlockCompressedDdsDecodes()
        {
            using (var stream = new MemoryStream(CreateRedDxt1Dds()))
            using (IImage image = Pfimage.FromStream(stream))
            using (Bitmap bitmap = DdsBitmapConverter.CreateThumbnail(image, 4))
            {
                Assert(bitmap.Size == new Size(4, 4), "Unexpected DXT1 bitmap dimensions.");
                Assert(bitmap.GetPixel(2, 2).ToArgb() == Color.Red.ToArgb(), "DXT1 red block was not decoded correctly.");
            }
        }

        private static void MipmappedDdsDecodesThroughOffsetLimitedStream()
        {
            byte[] dds = CreateMipmappedBgra32Dds();
            using (var limitedStream = new OffsetLimitedStream(dds))
            using (MemoryStream decoderStream = DdsStreamBuffer.CreateDecoderStream(limitedStream))
            using (IImage image = Pfimage.FromStream(decoderStream))
            {
                Assert(image.SizeIs(4, 4), "Unexpected mipmapped DDS dimensions.");
                Assert(image.MipMaps.Length == 2, "Mipmaps were not decoded from the buffered COM-style stream.");
            }
        }

        private static void MipmappedDdsDecodesThroughThumbnailComInterfaces()
        {
            VerifyBytesThroughThumbnailComInterfaces(CreateMipmappedBgra32Dds(), "Synthetic mipmapped DDS");
        }

        private static void VerifyDirectoryThroughThumbnailComInterfaces(string directoryPath)
        {
            if (!Directory.Exists(directoryPath))
            {
                throw new DirectoryNotFoundException(directoryPath);
            }

            string[] files = Directory.GetFiles(directoryPath, "*.dds", SearchOption.AllDirectories);
            Assert(files.Length != 0, "No DDS files were found in " + directoryPath);

            foreach (string filePath in files)
            {
                VerifyBytesThroughThumbnailComInterfaces(File.ReadAllBytes(filePath), filePath);
            }

            Console.WriteLine("Verified {0} real DDS files through the thumbnail COM interfaces.", files.Length);
        }

        private static void VerifyBytesThroughThumbnailComInterfaces(byte[] bytes, string description)
        {
            var handler = new DdsThumbnailHandler();
            var stream = new MemoryComStream(bytes);
            int initializeResult = ((IInitializeWithStream)handler).Initialize(stream, 0);
            Assert(initializeResult == 0, description + ": IInitializeWithStream failed: 0x" + initializeResult.ToString("X8"));

            IntPtr bitmapHandle = IntPtr.Zero;
            WTS_ALPHATYPE alphaType;
            try
            {
                int thumbnailResult = ((IThumbnailProvider)handler).GetThumbnail(256, out bitmapHandle, out alphaType);
                Assert(thumbnailResult == 0, description + ": IThumbnailProvider failed: 0x" + thumbnailResult.ToString("X8"));
                Assert(bitmapHandle != IntPtr.Zero, description + ": IThumbnailProvider returned no bitmap.");

                using (Bitmap bitmap = Bitmap.FromHbitmap(bitmapHandle))
                {
                    Assert(bitmap.Width > 0 && bitmap.Height > 0, description + ": COM thumbnail has invalid dimensions.");
                }
            }
            finally
            {
                if (bitmapHandle != IntPtr.Zero)
                {
                    DeleteObject(bitmapHandle);
                }

                stream.Dispose();
            }
        }

        private static byte[] CreateBgra32Dds(int width, int height, byte[] pixels)
        {
            int expectedLength = checked(width * height * 4);
            if (pixels.Length != expectedLength)
            {
                throw new ArgumentException("Pixel buffer has the wrong length.", nameof(pixels));
            }

            var bytes = new byte[128 + pixels.Length];
            bytes[0] = (byte)'D';
            bytes[1] = (byte)'D';
            bytes[2] = (byte)'S';
            bytes[3] = (byte)' ';
            WriteUInt32(bytes, 4, 124);
            WriteUInt32(bytes, 8, 0x0000100F);
            WriteUInt32(bytes, 12, (uint)height);
            WriteUInt32(bytes, 16, (uint)width);
            WriteUInt32(bytes, 20, (uint)(width * 4));
            WriteUInt32(bytes, 76, 32);
            WriteUInt32(bytes, 80, 0x41);
            WriteUInt32(bytes, 88, 32);
            WriteUInt32(bytes, 92, 0x00FF0000);
            WriteUInt32(bytes, 96, 0x0000FF00);
            WriteUInt32(bytes, 100, 0x000000FF);
            WriteUInt32(bytes, 104, 0xFF000000);
            WriteUInt32(bytes, 108, 0x1000);
            Buffer.BlockCopy(pixels, 0, bytes, 128, pixels.Length);
            return bytes;
        }

        private static byte[] CreateRedDxt1Dds()
        {
            var bytes = new byte[136];
            bytes[0] = (byte)'D';
            bytes[1] = (byte)'D';
            bytes[2] = (byte)'S';
            bytes[3] = (byte)' ';
            WriteUInt32(bytes, 4, 124);
            WriteUInt32(bytes, 8, 0x00081007);
            WriteUInt32(bytes, 12, 4);
            WriteUInt32(bytes, 16, 4);
            WriteUInt32(bytes, 20, 8);
            WriteUInt32(bytes, 76, 32);
            WriteUInt32(bytes, 80, 0x4);
            WriteUInt32(bytes, 84, 0x31545844); // "DXT1"
            WriteUInt32(bytes, 108, 0x1000);

            // One BC1 block: RGB565 red and green endpoints, with every index selecting red.
            bytes[128] = 0x00;
            bytes[129] = 0xF8;
            bytes[130] = 0xE0;
            bytes[131] = 0x07;
            return bytes;
        }

        private static byte[] CreateMipmappedBgra32Dds()
        {
            byte[] basePixels = new byte[4 * 4 * 4];
            byte[] baseDds = CreateBgra32Dds(4, 4, basePixels);
            var result = new byte[baseDds.Length + (2 * 2 * 4) + 4];
            Buffer.BlockCopy(baseDds, 0, result, 0, baseDds.Length);
            WriteUInt32(result, 8, 0x0002100F);
            WriteUInt32(result, 28, 3);
            WriteUInt32(result, 108, 0x00401008);
            return result;
        }

        private static void WriteUInt32(byte[] bytes, int offset, uint value)
        {
            bytes[offset] = (byte)value;
            bytes[offset + 1] = (byte)(value >> 8);
            bytes[offset + 2] = (byte)(value >> 16);
            bytes[offset + 3] = (byte)(value >> 24);
        }

        private static void Assert(bool condition, string message)
        {
            if (!condition)
            {
                throw new InvalidOperationException(message);
            }
        }

        private static bool SizeIs(this IImage image, int width, int height)
        {
            return image.Width == width && image.Height == height;
        }

        [DllImport("gdi32.dll")]
        private static extern bool DeleteObject(IntPtr objectHandle);

        private sealed class MemoryComStream : ComTypes.IStream, IDisposable
        {
            private readonly MemoryStream inner;

            internal MemoryComStream(byte[] bytes)
            {
                inner = new MemoryStream(bytes, false);
            }

            public void Read(byte[] buffer, int count, IntPtr bytesRead)
            {
                int actual = inner.Read(buffer, 0, count);
                if (bytesRead != IntPtr.Zero)
                {
                    Marshal.WriteInt32(bytesRead, actual);
                }
            }

            public void Write(byte[] buffer, int count, IntPtr bytesWritten)
            {
                throw new NotSupportedException();
            }

            public void Seek(long offset, int origin, IntPtr newPosition)
            {
                long position = inner.Seek(offset, (SeekOrigin)origin);
                if (newPosition != IntPtr.Zero)
                {
                    Marshal.WriteInt64(newPosition, position);
                }
            }

            public void SetSize(long value)
            {
                throw new NotSupportedException();
            }

            public void CopyTo(ComTypes.IStream target, long count, IntPtr bytesRead, IntPtr bytesWritten)
            {
                throw new NotSupportedException();
            }

            public void Commit(int flags)
            {
            }

            public void Revert()
            {
                throw new NotSupportedException();
            }

            public void LockRegion(long offset, long count, int lockType)
            {
                throw new NotSupportedException();
            }

            public void UnlockRegion(long offset, long count, int lockType)
            {
                throw new NotSupportedException();
            }

            public void Stat(out ComTypes.STATSTG statistics, int flags)
            {
                statistics = new ComTypes.STATSTG
                {
                    cbSize = inner.Length,
                    type = 2
                };
            }

            public void Clone(out ComTypes.IStream clone)
            {
                throw new NotSupportedException();
            }

            public void Dispose()
            {
                inner.Dispose();
            }
        }

        private sealed class OffsetLimitedStream : Stream
        {
            private readonly MemoryStream inner;

            internal OffsetLimitedStream(byte[] bytes)
            {
                inner = new MemoryStream(bytes, false);
            }

            public override int Read(byte[] buffer, int offset, int count)
            {
                if (offset != 0)
                {
                    throw new NotImplementedException("Non-zero read offsets are not supported.");
                }

                return inner.Read(buffer, offset, count);
            }

            public override bool CanRead => true;
            public override bool CanSeek => true;
            public override bool CanWrite => false;
            public override long Length => inner.Length;
            public override long Position { get => inner.Position; set => inner.Position = value; }
            public override void Flush() { }
            public override long Seek(long offset, SeekOrigin origin) => inner.Seek(offset, origin);
            public override void SetLength(long value) => throw new NotSupportedException();
            public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

            protected override void Dispose(bool disposing)
            {
                if (disposing)
                {
                    inner.Dispose();
                }

                base.Dispose(disposing);
            }
        }
    }
}
