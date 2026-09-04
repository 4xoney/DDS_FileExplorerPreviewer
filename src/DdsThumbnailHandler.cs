using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using Pfim;
using SharpShell.Attributes;
using SharpShell.SharpThumbnailHandler;

namespace DdsThumbnailProvider
{
    [ComVisible(true)]
    [Guid("4AB9224A-8A69-44A2-B65A-F1BB0D7AF38E")]
#pragma warning disable CS0618 // Direct extension registration is intentional; it survives UserChoice ProgID changes.
    [COMServerAssociation(AssociationType.FileExtension, ".dds")]
#pragma warning restore CS0618
    public sealed class DdsThumbnailHandler : SharpThumbnailHandler
    {
        private const uint MaximumExplorerThumbnailSize = 4096;

        protected override Bitmap GetThumbnailImage(uint width)
        {
            if (width == 0)
            {
                return null;
            }

            try
            {
                // SharpShell's COM stream wrapper rejects Read calls with a non-zero
                // buffer offset. Pfim legitimately uses such reads for mipmapped DDS
                // data, so first make a normal seekable managed copy.
                using (MemoryStream ddsStream = DdsStreamBuffer.CreateDecoderStream(SelectedItemStream))
                {
                    string validationError;
                    if (!DdsHeaderValidator.TryValidate(ddsStream, out validationError))
                    {
                        Log("DDS thumbnail skipped: " + validationError);
                        return null;
                    }

                    int requestedSize = checked((int)Math.Min(width, MaximumExplorerThumbnailSize));
                    ddsStream.Position = 0;
                    using (IImage image = Pfimage.FromStream(ddsStream))
                    {
                        return DdsBitmapConverter.CreateThumbnail(image, requestedSize);
                    }
                }
            }
            catch (Exception exception)
            {
                LogError("Could not create a DDS thumbnail.", exception);
                return null;
            }
        }
    }
}
