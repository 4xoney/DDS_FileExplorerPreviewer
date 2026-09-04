using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using Pfim;
using PfimImageFormat = Pfim.ImageFormat;

namespace DdsThumbnailProvider
{
    internal static class DdsBitmapConverter
    {
        internal static Bitmap CreateThumbnail(IImage image, int requestedSize)
        {
            if (image == null)
            {
                throw new ArgumentNullException(nameof(image));
            }

            if (requestedSize <= 0)
            {
                throw new ArgumentOutOfRangeException(nameof(requestedSize));
            }

            ValidateImageBuffer(image);

            using (Bitmap source = CreateArgbBitmap(image))
            {
                Size thumbnailSize = CalculateThumbnailSize(image.Width, image.Height, requestedSize);
                if (thumbnailSize.Width == source.Width && thumbnailSize.Height == source.Height)
                {
                    return source.Clone(new Rectangle(0, 0, source.Width, source.Height), PixelFormat.Format32bppArgb);
                }

                var result = new Bitmap(thumbnailSize.Width, thumbnailSize.Height, PixelFormat.Format32bppArgb);
                using (Graphics graphics = Graphics.FromImage(result))
                {
                    graphics.CompositingMode = CompositingMode.SourceCopy;
                    graphics.CompositingQuality = CompositingQuality.HighQuality;
                    graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    graphics.SmoothingMode = SmoothingMode.HighQuality;
                    graphics.DrawImage(
                        source,
                        new Rectangle(0, 0, result.Width, result.Height),
                        new Rectangle(0, 0, source.Width, source.Height),
                        GraphicsUnit.Pixel);
                }

                return result;
            }
        }

        internal static Size CalculateThumbnailSize(int width, int height, int requestedSize)
        {
            if (width <= 0 || height <= 0 || requestedSize <= 0)
            {
                throw new ArgumentOutOfRangeException("Image dimensions and requested size must be positive.");
            }

            double scale = Math.Min(1.0, (double)requestedSize / Math.Max(width, height));
            return new Size(
                Math.Max(1, (int)Math.Round(width * scale)),
                Math.Max(1, (int)Math.Round(height * scale)));
        }

        private static Bitmap CreateArgbBitmap(IImage image)
        {
            var bitmap = new Bitmap(image.Width, image.Height, PixelFormat.Format32bppArgb);
            var bounds = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
            BitmapData bitmapData = bitmap.LockBits(bounds, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);

            try
            {
                try
                {
                    var outputRow = new byte[checked(image.Width * 4)];
                    for (int y = 0; y < image.Height; y++)
                    {
                        ConvertRow(image, y, outputRow);
                        Marshal.Copy(outputRow, 0, IntPtr.Add(bitmapData.Scan0, y * bitmapData.Stride), outputRow.Length);
                    }
                }
                finally
                {
                    bitmap.UnlockBits(bitmapData);
                }
            }
            catch
            {
                bitmap.Dispose();
                throw;
            }
            return bitmap;
        }

        private static void ConvertRow(IImage image, int y, byte[] output)
        {
            byte[] input = image.Data;
            int source = checked(y * image.Stride);

            for (int x = 0; x < image.Width; x++)
            {
                int destination = x * 4;
                switch (image.Format)
                {
                    case PfimImageFormat.Rgba32:
                        CopyBgra(input, source + (x * 4), output, destination);
                        break;
                    case PfimImageFormat.Rgb24:
                        CopyBgr(input, source + (x * 3), output, destination);
                        break;
                    case PfimImageFormat.Rgb8:
                        CopyGray(input[source + x], output, destination);
                        break;
                    case PfimImageFormat.R5g5b5:
                        CopyRgb555(ReadUInt16(input, source + (x * 2)), false, output, destination);
                        break;
                    case PfimImageFormat.R5g6b5:
                        CopyRgb565(ReadUInt16(input, source + (x * 2)), output, destination);
                        break;
                    case PfimImageFormat.R5g5b5a1:
                        CopyRgb555(ReadUInt16(input, source + (x * 2)), true, output, destination);
                        break;
                    case PfimImageFormat.Rgba16:
                        CopyBgra4444(ReadUInt16(input, source + (x * 2)), output, destination);
                        break;
                    case PfimImageFormat.R16f:
                        CopyFloatGray(HalfToSingle(ReadUInt16(input, source + (x * 2))), output, destination);
                        break;
                    case PfimImageFormat.R32f:
                        CopyFloatGray(BitConverter.ToSingle(input, source + (x * 4)), output, destination);
                        break;
                    default:
                        throw new NotSupportedException("Unsupported Pfim pixel format: " + image.Format);
                }
            }
        }

        private static void ValidateImageBuffer(IImage image)
        {
            if (image.Width <= 0 || image.Height <= 0 || image.Stride <= 0 || image.Data == null)
            {
                throw new InvalidDataException("Pfim returned invalid image dimensions or data.");
            }

            int bytesPerPixel = BytesPerPixel(image.Format);
            long rowBytes = (long)image.Width * bytesPerPixel;
            long requiredBytes = ((long)image.Height - 1) * image.Stride + rowBytes;
            int availableBytes = Math.Min(image.DataLen, image.Data.Length);
            if (image.Stride < rowBytes || requiredBytes > availableBytes)
            {
                throw new InvalidDataException("Pfim returned an incomplete image buffer.");
            }
        }

        private static int BytesPerPixel(PfimImageFormat format)
        {
            switch (format)
            {
                case PfimImageFormat.Rgb8:
                    return 1;
                case PfimImageFormat.R5g5b5:
                case PfimImageFormat.R5g6b5:
                case PfimImageFormat.R5g5b5a1:
                case PfimImageFormat.Rgba16:
                case PfimImageFormat.R16f:
                    return 2;
                case PfimImageFormat.Rgb24:
                    return 3;
                case PfimImageFormat.Rgba32:
                case PfimImageFormat.R32f:
                    return 4;
                default:
                    throw new NotSupportedException("Unsupported Pfim pixel format: " + format);
            }
        }

        private static void CopyBgra(byte[] input, int source, byte[] output, int destination)
        {
            output[destination] = input[source];
            output[destination + 1] = input[source + 1];
            output[destination + 2] = input[source + 2];
            output[destination + 3] = input[source + 3];
        }

        private static void CopyBgr(byte[] input, int source, byte[] output, int destination)
        {
            output[destination] = input[source];
            output[destination + 1] = input[source + 1];
            output[destination + 2] = input[source + 2];
            output[destination + 3] = 255;
        }

        private static void CopyGray(byte gray, byte[] output, int destination)
        {
            output[destination] = gray;
            output[destination + 1] = gray;
            output[destination + 2] = gray;
            output[destination + 3] = 255;
        }

        private static void CopyFloatGray(float value, byte[] output, int destination)
        {
            byte gray;
            if (float.IsNaN(value) || value <= 0f)
            {
                gray = 0;
            }
            else if (value >= 1f)
            {
                gray = 255;
            }
            else
            {
                gray = (byte)Math.Round(value * 255f);
            }

            CopyGray(gray, output, destination);
        }

        private static void CopyRgb555(ushort pixel, bool hasAlpha, byte[] output, int destination)
        {
            output[destination] = Expand5(pixel & 0x1F);
            output[destination + 1] = Expand5((pixel >> 5) & 0x1F);
            output[destination + 2] = Expand5((pixel >> 10) & 0x1F);
            output[destination + 3] = !hasAlpha || (pixel & 0x8000) != 0 ? (byte)255 : (byte)0;
        }

        private static void CopyRgb565(ushort pixel, byte[] output, int destination)
        {
            output[destination] = Expand5(pixel & 0x1F);
            output[destination + 1] = Expand6((pixel >> 5) & 0x3F);
            output[destination + 2] = Expand5((pixel >> 11) & 0x1F);
            output[destination + 3] = 255;
        }

        private static void CopyBgra4444(ushort pixel, byte[] output, int destination)
        {
            output[destination] = Expand4(pixel & 0xF);
            output[destination + 1] = Expand4((pixel >> 4) & 0xF);
            output[destination + 2] = Expand4((pixel >> 8) & 0xF);
            output[destination + 3] = Expand4((pixel >> 12) & 0xF);
        }

        private static byte Expand4(int value) => (byte)(value * 17);
        private static byte Expand5(int value) => (byte)((value * 255 + 15) / 31);
        private static byte Expand6(int value) => (byte)((value * 255 + 31) / 63);

        private static ushort ReadUInt16(byte[] bytes, int offset)
        {
            return (ushort)(bytes[offset] | (bytes[offset + 1] << 8));
        }

        private static float HalfToSingle(ushort value)
        {
            int sign = (value >> 15) & 1;
            int exponent = (value >> 10) & 0x1F;
            int mantissa = value & 0x3FF;

            if (exponent == 0)
            {
                if (mantissa == 0)
                {
                    return sign == 0 ? 0f : -0f;
                }

                return (sign == 0 ? 1f : -1f) * (float)(mantissa / 1024.0 * Math.Pow(2, -14));
            }

            if (exponent == 31)
            {
                return mantissa == 0
                    ? (sign == 0 ? float.PositiveInfinity : float.NegativeInfinity)
                    : float.NaN;
            }

            return (sign == 0 ? 1f : -1f) * (float)((1.0 + mantissa / 1024.0) * Math.Pow(2, exponent - 15));
        }
    }
}
